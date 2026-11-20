//! Remove a slice or array bounds-check assert that a dominating comparison already proved.
//!
//! The existing `SsaRangePropagation` pass only records singleton equality facts over SSA
//! locals, so it cannot discharge the bounds check of a loop: a loop counter is a mutable
//! local by construction, and the assert re-tests the relation through fresh copies rather
//! than reusing the boolean the loop guard computed.
//!
//! This pass carries the relation itself, as a forward must-analysis over `a < b` facts.
//! Facts enter a block from its reachable predecessors, flow through its statements, and are
//! extended on an edge by whatever the terminator proves. At a bounds-check assert whose
//! relation is already in the set, the assert is replaced by a goto to its success target.
//! The panic edge is unreachable once the relation is proved, which is the same rewrite
//! `SimplifyConstCondition` performs for a constant condition.
//!
//! Relations range over enum payloads, not just locals, because that is what a `for` loop
//! needs. `for i in 0..n` desugars to an iterator whose `next` returns `Option<usize>`, so the
//! index is laundered through `_4 = Some(copy _10)` and read back as
//! `_6 = copy ((_4 as Some).0)`. Tracking locals alone loses the relation at exactly that
//! round trip, which is why a `while` loop proves and a `for` loop does not.
//!
//! A fixpoint is needed rather than a glance at the immediate predecessor. The loop guard
//! proves its relation on one edge but the assert sits several blocks later behind plain
//! gotos, which prove nothing on their own, so the fact has to travel.
//!
//! Unreachable predecessors are skipped. Threading leaves behind blocks that still name the
//! assert block as a successor while nothing branches to them, and meeting a dead block's
//! empty fact set would collapse the intersection and silently prove nothing.
//!
//! Soundness rests on five rules. A fact only enters a block when every reachable predecessor
//! offers it. A write to a local kills every fact naming it, including through one of its
//! fields, so a relation never crosses an assignment that could falsify it. A copy carries the
//! source's relations onto the target, so a value captured before its source is overwritten
//! keeps what was proved, which is what a loop does when it captures the counter before
//! advancing it. A payload relation records the variant it was built under and is only read
//! back through a downcast to that same variant. And an edge fact is dropped when a statement
//! after the comparison writes either operand, so a guard that tested a stale value proves
//! nothing.
//!
//! Relations are held in vectors rather than hash sets. They number a handful at most, and a
//! vector keeps iteration order deterministic, which `rustc::potential_query_instability`
//! requires of anything a query result depends on.

use rustc_index::IndexVec;
use rustc_middle::mir::*;
use rustc_middle::ty::{self, TyCtxt};

use crate::PassPolicy;

pub(super) struct BoundsCheckElision;

/// One side of a relation: a local, or a field of one under a given variant.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Ref {
    Local(Local),
    Field(Local, u32, u32),
    Const(u128),
}

impl Ref {
    /// The local this side reads, or `None` for a literal, which no write can disturb.
    fn base(self) -> Option<Local> {
        match self {
            Ref::Local(local) | Ref::Field(local, _, _) => Some(local),
            Ref::Const(_) => None,
        }
    }
}

/// `.0 < .1` when `.2`, otherwise `.0 <= .1`.
type Fact = (Ref, Ref, bool);


/// `.0` currently stands for `.1`, built by walking a block's copies in order.
type Alias = Vec<(Local, Local)>;

/// The most relations held at once, anywhere.
///
/// A real body can offer far more comparisons than a bounds check needs, and the transitive
/// closure of them is quadratic. Dropping a relation only ever costs a proof, never soundness,
/// so a cap keeps the pass cheap on functions that compare a great deal.
const MAX_FACTS: usize = 64;

impl<'tcx> crate::MirPass<'tcx> for BoundsCheckElision {
    fn policy(&self, sess: &rustc_session::Session) -> PassPolicy {
        PassPolicy::optimization(sess.mir_opt_level() > 1)
    }

    fn run_pass(&self, tcx: TyCtxt<'tcx>, body: &mut Body<'tcx>) {
        let live = reachable(body);
        let entry = solve(tcx, body, &live);

        let mut proven: Vec<(BasicBlock, BasicBlock)> = Vec::new();
        for (bb, data) in body.basic_blocks.iter_enumerated() {
            if !live[bb] {
                continue;
            }
            let Some(terminator) = &data.terminator else { continue };
            let TerminatorKind::Assert { cond, expected: true, target, .. } = &terminator.kind
            else {
                continue;
            };
            let Some(cond) = operand_local(cond) else { continue };
            let Some((index, lhs, rhs, _)) = cmp_assignment(data, cond) else { continue };

            let mut facts = entry[bb].clone().unwrap_or_default();
            if facts.is_empty() {
                continue;
            }
            let alias = walk(data, index, &mut facts);
            close(&mut facts);
            let direct = (lhs, rhs, true);
            let rooted = (root_ref(&alias, lhs), root_ref(&alias, rhs), true);
            if facts.contains(&direct)
                || facts.contains(&rooted)
                || proved_by_offset(body, &facts, &alias, rooted.0, rooted.1)
                || proved_by_equal_bound(body, &facts, rooted.0, rooted.1, bb)
                || proved_by_max(tcx, body, &facts, rooted.0, rooted.1)
            {
                proven.push((bb, *target));
            }
        }

        if proven.is_empty() {
            return;
        }
        let blocks = body.basic_blocks_mut();
        for (bb, target) in proven {
            blocks[bb].terminator_mut().kind = TerminatorKind::Goto { target };
        }
    }
}

/// The blocks reachable from the entry block.
fn reachable<'tcx>(body: &Body<'tcx>) -> IndexVec<BasicBlock, bool> {
    let mut live = IndexVec::from_elem_n(false, body.basic_blocks.len());
    let mut stack = vec![START_BLOCK];
    live[START_BLOCK] = true;
    while let Some(bb) = stack.pop() {
        if let Some(terminator) = &body.basic_blocks[bb].terminator {
            for succ in terminator.successors() {
                if !live[succ] {
                    live[succ] = true;
                    stack.push(succ);
                }
            }
        }
    }
    live
}

/// The facts holding on entry to each reachable block, as a least fixpoint.
///
/// `None` marks a block not yet reached by the solver, which is the top of the lattice: the
/// first predecessor to offer facts sets them, and every later one intersects.
///
/// The solver is given a step budget, and exhausting it yields no facts at all rather than the
/// ones computed so far. Fact sets here are refined downward from an optimistic start, so an
/// unfinished fixpoint can still name a relation that some predecessor does not offer; keeping
/// those would let a fallible check be removed. Proving nothing is the only sound way to stop
/// early, and it keeps a pathological body from stalling the compiler.
fn solve<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    live: &IndexVec<BasicBlock, bool>,
) -> IndexVec<BasicBlock, Option<Vec<Fact>>> {
    solve_seeded(tcx, body, live, &[], 0)
}

/// `solve` with the entry block pre-loaded, which is what makes a callee summary context
/// sensitive. A summary computed with no assumptions is often too weak to be worth anything:
/// `fn last(n) { if n == 0 { 0 } else { n - 1 } }` returns `n - 1` on one path and `0` on the
/// other, so the only relation true on both is `result <= n`, and that never discharges an
/// index. Seeded with the caller's own knowledge that `0 < n`, the zero path becomes
/// contradictory, is dropped, and the surviving path gives the strict `result < n` the check
/// actually needs.
fn solve_seeded<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    live: &IndexVec<BasicBlock, bool>,
    seed: &[Fact],
    depth: u32,
) -> IndexVec<BasicBlock, Option<Vec<Fact>>> {
    let mut entry: IndexVec<BasicBlock, Option<Vec<Fact>>> =
        IndexVec::from_elem_n(None, body.basic_blocks.len());
    let mut start = seed.to_vec();
    close(&mut start);
    entry[START_BLOCK] = Some(start);

    let budget = body.basic_blocks.len().saturating_mul(64).saturating_add(1024);
    let mut steps = 0usize;

    let mut worklist = vec![START_BLOCK];
    while let Some(bb) = worklist.pop() {
        steps += 1;
        if steps > budget {
            return IndexVec::from_elem_n(None, body.basic_blocks.len());
        }
        if !live[bb] {
            continue;
        }
        // A block whose facts cannot all hold at once is not reachable under the seed, so it
        // must not contribute to any intersection downstream.
        if entry[bb].as_ref().is_some_and(|facts| contradictory(facts)) {
            continue;
        }
        let data = &body.basic_blocks[bb];
        let Some(terminator) = &data.terminator else { continue };

        let mut exit = entry[bb].clone().unwrap_or_default();
        walk(data, data.statements.len(), &mut exit);

        // A call assigns its destination at the terminator, which `walk` never reaches because
        // it only reads statements. Without this kill a relation naming that local would
        // survive the call that overwrote it, and a stale relation discharges a live check.
        if let TerminatorKind::Call { destination, .. } = &terminator.kind {
            let clobbered = destination.local;
            exit.retain(|&(lhs, rhs, _)| {
                lhs.base() != Some(clobbered) && rhs.base() != Some(clobbered)
            });
        }

        for succ in terminator.successors() {
            if !live[succ] {
                continue;
            }
            let mut proposed = exit.clone();
            for fact in edge_facts(body, data, succ)
                .into_iter()
                .chain(call_facts(tcx, body, data, succ, &exit, depth))
            {
                if proposed.len() < MAX_FACTS && !proposed.contains(&fact) {
                    proposed.push(fact);
                }
            }
            close(&mut proposed);
            let changed = match &mut entry[succ] {
                slot @ None => {
                    *slot = Some(proposed);
                    true
                }
                Some(have) => {
                    let before = have.len();
                    have.retain(|fact| proposed.contains(fact));
                    have.len() != before
                }
            };
            if changed {
                worklist.push(succ);
            }
        }
    }
    entry
}

/// The statement assigning `cond` from a `Lt`, with the two operand locals as written.
///
/// The block is scanned from the end so the latest assignment to `cond` wins, which is the one
/// the terminator reads. Storage bookkeeping between that statement and the terminator is
/// skipped rather than treated as a mismatch.
fn cmp_assignment<'tcx>(
    data: &BasicBlockData<'tcx>,
    cond: Local,
) -> Option<(usize, Ref, Ref, bool)> {
    for (index, statement) in data.statements.iter().enumerate().rev() {
        let StatementKind::Assign(assignment) = &statement.kind else { continue };
        let (place, rvalue) = &**assignment;
        if place.local != cond || !place.projection.is_empty() {
            continue;
        }
        let Rvalue::BinaryOp(op, operands) = rvalue else { return None };
        let (lhs, rhs) = &**operands;
        // `a > b` is `b < a` and `a >= b` is `b <= a`, so both normalize by swapping sides.
        let (lhs, rhs, strict) = match op {
            BinOp::Lt => (lhs, rhs, true),
            BinOp::Le => (lhs, rhs, false),
            BinOp::Gt => (rhs, lhs, true),
            BinOp::Ge => (rhs, lhs, false),
            _ => return None,
        };
        return Some((index, operand_side(lhs)?, operand_side(rhs)?, strict));
    }
    None
}

/// The local an operand reads directly, with no projection.
fn operand_local<'tcx>(operand: &Operand<'tcx>) -> Option<Local> {
    let place = operand.place()?;
    place.projection.is_empty().then_some(place.local)
}

/// The relation side a place denotes: a bare local, or one field under one variant.
fn place_ref(place: &Place<'_>) -> Option<Ref> {
    match place.projection.as_slice() {
        [] => Some(Ref::Local(place.local)),
        [ProjectionElem::Downcast(_, variant), ProjectionElem::Field(field, _)] => {
            Some(Ref::Field(place.local, variant.as_u32(), field.as_u32()))
        }
        [ProjectionElem::Field(field, _)] => Some(Ref::Field(place.local, 0, field.as_u32())),
        _ => None,
    }
}

/// The relation side an operand reads, if it reads one at all.
fn operand_ref<'tcx>(operand: &Operand<'tcx>) -> Option<Ref> {
    place_ref(&operand.place()?)
}

/// The unsigned value of a literal operand.
fn operand_const<'tcx>(operand: &Operand<'tcx>) -> Option<u128> {
    let int = operand.constant()?.const_.try_to_scalar_int()?;
    Some(int.to_uint(int.size()))
}

/// The relation side an operand denotes, literal or read.
fn operand_side<'tcx>(operand: &Operand<'tcx>) -> Option<Ref> {
    match operand_const(operand) {
        Some(value) => Some(Ref::Const(value)),
        None => operand_ref(operand),
    }
}

/// `root_of` lifted to a relation side; a literal stands for itself.
fn root_ref(alias: &Alias, side: Ref) -> Ref {
    match side {
        Ref::Local(local) => Ref::Local(root_of(alias, local)),
        other => other,
    }
}

/// What `local` stands for after the copies walked so far, or itself.
fn root_of(alias: &Alias, local: Local) -> Local {
    alias.iter().find(|(from, _)| *from == local).map_or(local, |(_, root)| *root)
}

/// Whether any statement after `from` assigns `local`.
fn written_after<'tcx>(data: &BasicBlockData<'tcx>, from: usize, local: Local) -> bool {
    data.statements.iter().skip(from + 1).any(|statement| {
        matches!(&statement.kind, StatementKind::Assign(assignment)
            if assignment.0.local == local && assignment.0.projection.is_empty())
    })
}

/// The relations this block's terminator proves on the edge into `succ`, over root locals.
fn edge_facts<'tcx>(
    body: &Body<'tcx>,
    data: &BasicBlockData<'tcx>,
    succ: BasicBlock,
) -> Vec<Fact> {
    let Some(terminator) = &data.terminator else { return Vec::new() };
    let proves = match &terminator.kind {
        // A `switchInt` on a `Lt` boolean proves the relation on the edge taken when that
        // boolean is true, which is the `otherwise` target once zero goes elsewhere.
        TerminatorKind::SwitchInt { discr, targets } => {
            let taken = targets.otherwise() == succ && targets.target_for_value(0) != succ;
            let refuted = targets.target_for_value(0) == succ && targets.otherwise() != succ;
            if refuted {
                // The comparison was false here, so the negation holds: `!(a < b)` is `b <= a`
                // and `!(a <= b)` is `b < a`. Both swap the sides and flip strictness.
                let Some(cond) = operand_local(discr) else { return Vec::new() };
                let Some((index, lhs, rhs, strict)) = cmp_assignment(data, cond) else {
                    // The switch is on a plain value rather than a comparison, and this is the
                    // arm it matched, so the value equals the literal here. Emitting nothing
                    // left the arm merely unconstrained, which is why a callee analysed under
                    // a seeded precondition still lost its strict bound: the arm the
                    // precondition rules out survived and diluted the intersection at return.
                    let side = Ref::Local(cond);
                    let zero = Ref::Const(0);
                    return vec![(side, zero, false), (zero, side, false)];
                };
                let alias = walk(data, index, &mut Vec::new());
                let (lhs, rhs) = (root_ref(&alias, lhs), root_ref(&alias, rhs));
                let disturbed = [lhs, rhs]
                    .into_iter()
                    .filter_map(Ref::base)
                    .any(|local| written_after(data, index, local));
                return if disturbed { Vec::new() } else { vec![(rhs, lhs, !strict)] };
            }
            taken.then(|| operand_local(discr)).flatten()
        }
        // A bounds-check assert that succeeded proves its own relation on the success edge.
        TerminatorKind::Assert { cond, expected: true, target, .. } if *target == succ => {
            operand_local(cond)
        }
        _ => None,
    };
    let Some(boolean) = proves else {
        return ne_zero_edge(body, data, succ).into_iter().collect();
    };
    // A switch on a plain value is not a comparison, so fall through to what such a switch
    // does prove rather than giving up. Returning here left `ne_zero_edge` unreachable, and
    // without `0 < len` no subtraction of one could ever be shown exact.
    let Some((index, lhs, rhs, strict)) = cmp_assignment(data, boolean) else {
        return ne_zero_edge(body, data, succ).into_iter().collect();
    };

    // Resolve the guard's own copies: it reads the counter and the length through temporaries.
    let alias = walk(data, index, &mut Vec::new());
    let (lhs, rhs) = (root_ref(&alias, lhs), root_ref(&alias, rhs));
    let disturbed = [lhs, rhs]
        .into_iter()
        .filter_map(Ref::base)
        .any(|local| written_after(data, index, local));
    if disturbed {
        return Vec::new();
    }
    let mut out = vec![(lhs, rhs, strict)];
    if strict {
        if let Some(local) = rhs.base() {
            let ty = body.local_decls[local].ty;
            if ty.is_integral() && !ty.is_signed() {
                out.push((Ref::Const(0), rhs, true));
            }
        }
    }
    out
}

/// The least value a relation against a literal proves for `of`.
///
/// A strict relation carries one more than it appears to: `0 < n` proves `n >= 1`, which is
/// exactly what a subtraction of one needs to be exact. Reading the literal alone loses that
/// and leaves provable cases unproved.
fn lower_bound(facts: &[Fact], of: Ref) -> Option<u128> {
    facts
        .iter()
        .filter_map(|&(low, high, strict)| match low {
            Ref::Const(value) if high == of => Some(value + u128::from(strict)),
            _ => None,
        })
        .max()
}

/// Add `fact` unless it is already recorded.
fn remember(facts: &mut Vec<Fact>, fact: Fact) {
    if facts.len() < MAX_FACTS && !facts.contains(&fact) {
        facts.push(fact);
    }
}

/// Every fact that holds of `to` because it now carries the value of `from`.
fn carried(facts: &[Fact], from: Ref, to: Ref) -> Vec<Fact> {
    facts
        .iter()
        .filter_map(|&(lhs, rhs, strict)| match (lhs == from, rhs == from) {
            (true, _) => Some((to, rhs, strict)),
            (_, true) => Some((lhs, to, strict)),
            _ => None,
        })
        .collect()
}

/// Walk `data`'s first `upto` statements, returning the aliases they establish and updating
/// `facts` as each statement kills or carries relations.
fn walk<'tcx>(data: &BasicBlockData<'tcx>, upto: usize, facts: &mut Vec<Fact>) -> Alias {
    let mut alias: Alias = Vec::new();
    for statement in data.statements.iter().take(upto) {
        let StatementKind::Assign(assignment) = &statement.kind else { continue };
        let (place, rvalue) = &**assignment;
        if !place.projection.is_empty() {
            continue;
        }
        let target = place.local;

        // Whatever the rvalue, relations and aliases naming the target no longer hold. A fact
        // about one of its fields dies with it, since the whole local is overwritten.
        facts.retain(|&(lhs, rhs, _)| lhs.base() != Some(target) && rhs.base() != Some(target));
        alias.retain(|&(from, root)| from != target && root != target);

        match rvalue {
            // A plain copy or move carries the source's relations onto the target. They are
            // materialised rather than left behind an alias, because a loop captures the
            // counter before advancing it and the captured copy must keep what was proved
            // once the counter itself is overwritten.
            Rvalue::Use(operand, _) => {
                if let Some(source) = operand_ref(operand) {
                    for fact in carried(facts, source, Ref::Local(target)) {
                        remember(facts, fact);
                    }
                    // The target holds the source's value, so it is bounded by it. Only this
                    // direction is kept: recording the converse too would make the relation
                    // symmetric, and symmetric pairs are what stop the fixpoint settling.
                    remember(facts, (Ref::Local(target), source, false));
                    if let Ref::Local(source) = source {
                        let root = root_of(&alias, source);
                        if root != target {
                            alias.push((target, root));
                        }
                    }
                }
            }
            // Taking a positive amount off a value puts the result below it, which is what
            // carries a decrementing counter's bound around a loop. `SubUnchecked` is rustc's
            // own promise that it cannot wrap; a plain `Sub` wraps in release, so that needs a
            // relation putting the source at or above the amount removed.
            //
            // Only the one relation is recorded, never the source's own. Carrying those would
            // claim `x < target` from `x < source`, and the whole point is that `target` sits
            // below `source`, so such a relation need not hold at all.
            Rvalue::BinaryOp(op @ (BinOp::Sub | BinOp::SubUnchecked), operands) => {
                let (from, by) = &**operands;
                if let (Some(source), Some(step)) = (operand_ref(from), operand_const(by)) {
                    let exact = matches!(op, BinOp::SubUnchecked)
                        || lower_bound(facts, source).is_some_and(|least| least >= step);
                    if step > 0 && exact && source != Ref::Local(target) {
                        remember(facts, (Ref::Local(target), source, true));
                    }
                }
            }
            // A remainder is strictly below its modulus whenever the modulus is positive, and a
            // quotient never exceeds its dividend. Both are interval-domain staples, and the
            // quotient's non-strict relation composes with a guard to give the strict one: an
            // index of `i / 2` under a guard proving `i < len` lands below `len` that way.
            Rvalue::BinaryOp(BinOp::Rem, operands) => {
                let (_, by) = &**operands;
                if let Some(modulus) = operand_ref(by) {
                    let positive = matches!(modulus, Ref::Const(value) if value > 0)
                        || lower_bound(facts, modulus).is_some_and(|least| least >= 1);
                    if positive && modulus != Ref::Local(target) {
                        remember(facts, (Ref::Local(target), modulus, true));
                    }
                }
            }
            Rvalue::BinaryOp(BinOp::Div, operands) => {
                let (from, by) = &**operands;
                if let (Some(source), Some(divisor)) = (operand_ref(from), operand_const(by)) {
                    let strict = divisor >= 2
                        && lower_bound(facts, source).is_some_and(|least| least >= 1);
                    if divisor >= 1 && source != Ref::Local(target) {
                        remember(facts, (Ref::Local(target), source, strict));
                    }
                }
            }
            // Building an aggregate carries each operand's relations onto the field it fills,
            // which is how the index survives being wrapped in `Some`.
            Rvalue::Aggregate(kind, operands) => {
                let variant = match &**kind {
                    AggregateKind::Adt(_, variant, ..) => variant.as_u32(),
                    _ => 0,
                };
                for (field, operand) in operands.iter_enumerated() {
                    let Some(source) = operand_ref(operand) else { continue };
                    let slot = Ref::Field(target, variant, field.as_u32());
                    for fact in carried(facts, source, slot) {
                        remember(facts, fact);
                    }
                }
            }
            _ => {}
        }
    }
    alias
}

/// Compose relations transitively: `a < b` with `b <= c` gives `a < c`.
///
/// A composition is strict when either half is, since `a <= b < c` and `a < b <= c` both put
/// `a` strictly below `c`. Growth is capped because the closure of a handful of relations is
/// small but quadratic, and a pass is not the place to spend unbounded time.
///
/// Whether these relations cannot all hold at once.
///
/// Two shapes are decidable without any arithmetic on symbols. A relation between two literals
/// is simply checked, and the transitive closure manufactures exactly those when a seeded
/// lower bound meets a guard pushing the other way. A value strictly below itself is the other.
fn contradictory(facts: &[Fact]) -> bool {
    let plainly_false = facts.iter().any(|&(low, high, strict)| match (low, high) {
        (Ref::Const(a), Ref::Const(b)) => {
            if strict {
                a >= b
            } else {
                a > b
            }
        }
        _ => strict && low == high,
    });
    if plainly_false {
        return true;
    }
    // Opposing relations cannot both hold once either is strict: `a < b` with `b <= a` is
    // impossible. This has to be checked directly rather than left to the closure, because the
    // closure deliberately refuses to compose a relation with its own reverse, which is exactly
    // the composition that would expose the contradiction. Without this the arm a seeded
    // precondition rules out stays live and dilutes the intersection at the callee's return.
    facts.iter().any(|&(a, b, strict)| {
        facts
            .iter()
            .any(|&(c, d, back)| a == d && b == c && (strict || back))
    })
}

fn close(facts: &mut Vec<Fact>) {
    const CAP: usize = MAX_FACTS;
    const ROUNDS: usize = 8;
    for _ in 0..ROUNDS {
        let mut grew = false;
        let snapshot = facts.clone();
        for &(a, b, left) in &snapshot {
            for &(c, d, right) in &snapshot {
                if b != c || a == d {
                    continue;
                }
                let composed = (a, d, left || right);
                if !facts.contains(&composed) {
                    facts.push(composed);
                    grew = true;
                }
            }
        }
        // `a < b` also gives `a <= b`. Without the weaker form, a loop whose entry proves a
        // bound loosely and whose back edge proves it strictly agrees on neither, and the
        // intersection at the header drops the invariant entirely.
        for &(a, b, strict) in &snapshot {
            let weaker = (a, b, false);
            if strict && !facts.contains(&weaker) {
                facts.push(weaker);
                grew = true;
            }
        }

        if !grew || facts.len() >= CAP {
            return;
        }
    }
}

/// The rvalue assigned to `local`, when exactly one statement in the body assigns it.
///
/// A local written twice has no single meaning to reason about, so it is refused rather than
/// guessed at. This walks the body, which is affordable only because it is reached for a check
/// that the proved relations did not already discharge.
fn sole_definition<'a, 'tcx>(body: &'a Body<'tcx>, local: Local) -> Option<&'a Rvalue<'tcx>> {
    let mut found = None;
    for data in body.basic_blocks.iter() {
        for statement in &data.statements {
            let StatementKind::Assign(assignment) = &statement.kind else { continue };
            let (place, rvalue) = &**assignment;
            if place.local == local && place.projection.is_empty() {
                if found.is_some() {
                    return None;
                }
                found = Some(rvalue);
            }
        }
    }
    found
}

/// Whether `index < bound` follows from a proved relation plus arithmetic on a literal.
///
/// The shape is a loop over a shortened bound that indexes at an offset: `for i in 0..n - k`
/// reading at `i + k`. The guard proves `i < n - k` and the check asks for `i + k < n`, which
/// the relations alone cannot bridge because neither side of the check is the side the guard
/// compared.
///
/// Two things make the step sound. The subtraction must not have wrapped, or `n - k` would be
/// enormous and the guard would prove nothing about `i + k`; a relation putting `n` at or above
/// `k` rules that out, and then `n - k` is exact. Given that, `i < n - k` gives `i + k < n`,
/// and the addition cannot overflow either, since `i + k` is below `n`.
/// Whether `index < bound` follows from `index` being whatever `max` returned.
///
/// The summary for `max` records that the result is at least each argument. That is a lower
/// bound, and a lower bound can never discharge a bounds check on its own. The useful direction
/// is the upper one, and it needs both arguments at once: `max(a, b) < c` exactly when `a < c`
/// and `b < c`. Being a question about one specific bound, it cannot be recorded as a fact at
/// the call the way the lower bound is, so it is asked here instead.
///
/// The local must be written by exactly one call and by no statement at all. Without that the
/// arguments recovered here need not be the ones that produced the value being indexed with.
fn proved_by_max<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    facts: &[Fact],
    index: Ref,
    bound: Ref,
) -> bool {
    let Some(indexed) = index.base() else { return false };
    for data in body.basic_blocks.iter() {
        for statement in &data.statements {
            let StatementKind::Assign(assignment) = &statement.kind else { continue };
            let (place, _) = &**assignment;
            if place.local == indexed {
                return false;
            }
        }
    }
    let mut call = None;
    for data in body.basic_blocks.iter() {
        let Some(terminator) = &data.terminator else { continue };
        let TerminatorKind::Call { func, args, destination, .. } = &terminator.kind else {
            continue;
        };
        if destination.local != indexed || !destination.projection.is_empty() {
            continue;
        }
        if call.is_some() {
            return false;
        }
        call = Some((func, args));
    }
    let Some((func, args)) = call else { return false };
    let Some((krate, item)) = callee_name(tcx, func) else { return false };
    if (krate != "core" && krate != "std") || item != "max" || args.len() != 2 {
        return false;
    }
    args.iter().all(|argument| {
        operand_side(&argument.node).is_some_and(|side| {
            facts
                .iter()
                .any(|&(low, high, strict)| low == side && high == bound && strict)
        })
    })
}

fn proved_by_offset<'tcx>(
    body: &Body<'tcx>,
    facts: &[Fact],
    alias: &Alias,
    index: Ref,
    bound: Ref,
) -> bool {
    let Ref::Local(indexed) = index else { return false };
    let Ref::Local(limit) = bound else { return false };
    let Some(Rvalue::BinaryOp(BinOp::Add, add)) = sole_definition(body, indexed) else {
        return false;
    };
    let (base, offset) = &**add;
    let Some(step) = operand_const(offset) else { return false };
    let Some(base) = operand_side(base).map(|side| root_ref(alias, side)) else { return false };

    // `bound` is at least `step`, so subtracting `step` from it is exact.
    if !lower_bound(facts, bound).is_some_and(|least| least >= step) {
        return false;
    }

    facts.iter().any(|&(lhs, rhs, strict)| {
        if !strict || lhs != base {
            return false;
        }
        let Ref::Local(shortened) = rhs else { return false };
        let Some(Rvalue::BinaryOp(BinOp::Sub, sub)) = sole_definition(body, shortened) else {
            return false;
        };
        let (from, by) = &**sub;
        operand_side(from) == Some(Ref::Local(limit)) && operand_const(by) == Some(step)
    })
}

/// The relation `0 < local` proved on the edge a `switchInt` takes when the local is not zero.
///
/// `if !s.is_empty()` does not reach the optimizer as a branch on a comparison: rustc switches
/// on the length itself and leaves the `Eq` dead, so the fact has to be read off the switch's
/// own value list. A switch listing zero alone proves the local positive on `otherwise`.
///
/// Only for an unsigned local, where differing from zero means exceeding it. A signed one
/// could be below, and a `bool` is not a quantity to compare at all.
fn ne_zero_edge<'tcx>(
    body: &Body<'tcx>,
    data: &BasicBlockData<'tcx>,
    succ: BasicBlock,
) -> Option<Fact> {
    let terminator = data.terminator.as_ref()?;
    let TerminatorKind::SwitchInt { discr, targets } = &terminator.kind else { return None };

    // This must be the edge for everything other than zero, and zero must lead elsewhere. A
    // switch listing anything besides zero says nothing simple here, and `target_for_value`
    // answers with `otherwise` for an unlisted zero, which this same test rejects.
    if targets.otherwise() != succ || targets.target_for_value(0) == succ {
        return None;
    }
    if targets.iter().count() != 1 {
        return None;
    }

    let local = operand_local(discr)?;
    let ty = body.local_decls[local].ty;
    if !ty.is_integral() || ty.is_signed() {
        return None;
    }
    Some((Ref::Const(0), Ref::Local(local), true))
}


/// Whether any block reachable from `from` is `goal`.
fn reaches<'tcx>(body: &Body<'tcx>, from: BasicBlock, goal: BasicBlock) -> bool {
    let mut seen = IndexVec::from_elem_n(false, body.basic_blocks.len());
    let mut stack = vec![from];
    seen[from] = true;
    while let Some(bb) = stack.pop() {
        if bb == goal {
            return true;
        }
        let Some(terminator) = &body.basic_blocks[bb].terminator else { continue };
        for succ in terminator.successors() {
            if !seen[succ] {
                seen[succ] = true;
                stack.push(succ);
            }
        }
    }
    false
}

/// Whether `cond` was assigned an equality between `a` and `b`, in either order.
fn tests_equality<'tcx>(
    data: &BasicBlockData<'tcx>,
    cond: Local,
    a: Local,
    b: Local,
) -> bool {
    for (index, statement) in data.statements.iter().enumerate().rev() {
        let StatementKind::Assign(assignment) = &statement.kind else { continue };
        let (place, rvalue) = &**assignment;
        if place.local != cond || !place.projection.is_empty() {
            continue;
        }
        let Rvalue::BinaryOp(BinOp::Eq, operands) = rvalue else { return false };
        let (lhs, rhs) = &**operands;
        let (Some(lhs), Some(rhs)) = (operand_local(lhs), operand_local(rhs)) else {
            return false;
        };
        let same = (lhs == a && rhs == b) || (lhs == b && rhs == a);
        return same && !written_after(data, index, lhs) && !written_after(data, index, rhs);
    }
    false
}

/// Whether `a` and `b` must be equal wherever block `at` runs.
///
/// `assert_eq!` leaves an equality test whose failing edge diverges into a panic, so a block
/// the test dominates can only have been reached by the edge where the equality held.
///
/// Dominance alone is not enough: the values must also still be the ones compared. Requiring a
/// single assignment for each gives that, since nothing can have rewritten them in between.
fn equality_enforced<'tcx>(body: &Body<'tcx>, a: Ref, b: Ref, at: BasicBlock) -> bool {
    let (Ref::Local(a), Ref::Local(b)) = (a, b) else { return false };
    if sole_definition(body, a).is_none() || sole_definition(body, b).is_none() {
        return false;
    }

    let dominators = body.basic_blocks.dominators();
    for (bb, data) in body.basic_blocks.iter_enumerated() {
        let Some(terminator) = &data.terminator else { continue };
        let TerminatorKind::SwitchInt { discr, targets } = &terminator.kind else { continue };
        let Some(cond) = operand_local(discr) else { continue };
        if !tests_equality(data, cond, a, b) || !dominators.dominates(bb, at) {
            continue;
        }
        // The edge taken when the equality is false must not lead to `at`.
        if !reaches(body, targets.target_for_value(0), at) {
            return true;
        }
    }
    false
}

/// Whether `index < bound` follows from `index` being below a bound held equal to it.
///
/// Indexing two slices under one `assert_eq!` on their lengths is the case: the loop guard
/// proves the counter below the first length, and the check on the second slice asks about the
/// other. The relation transfers because the two lengths are the same quantity.
fn proved_by_equal_bound<'tcx>(
    body: &Body<'tcx>,
    facts: &[Fact],
    index: Ref,
    bound: Ref,
    at: BasicBlock,
) -> bool {
    facts.iter().any(|&(lhs, rhs, strict)| {
        strict && lhs == index && rhs != bound && equality_enforced(body, rhs, bound, at)
    })
}

/// The defining crate and item name of the function a call names, when it names one statically.
///
/// `def_path_str` is a diagnostic helper and must not be called from an optimization pass: it
/// builds a diagnostic that nothing emits, and the diagnostic context asserts on drop that it
/// emitted everything it was given. That aborts the compiler. `crate_name` and `item_name` are
/// plain lookups and carry no such machinery.
///
/// The crate is part of the identity on purpose. Matching the bare name would also match a
/// local function someone happened to call `min`, and applying a summary to a body this pass
/// has never seen would be an assumption rather than a theorem.
fn callee_name<'tcx>(tcx: TyCtxt<'tcx>, func: &Operand<'tcx>) -> Option<(String, String)> {
    let ty = func.constant()?.const_.ty();
    match *ty.kind() {
        ty::FnDef(def_id, _) => Some((
            tcx.crate_name(def_id.krate).to_string(),
            tcx.item_name(def_id).to_string(),
        )),
        _ => None,
    }
}

/// The relations a known callee's postcondition proves about its own result.
///
/// This is the one mechanism a single-body analysis cannot supply. The inliner declines these
/// callees at this point in the pipeline, so the body holds an opaque `Call` and no comparison
/// relating the result to anything. Nothing in the function can prove the check; the proof
/// comes from what the callee is defined to return.
///
/// Each summary is a theorem about the callee, not a guess:
///   `min(a, b)` is at most either argument.
///   `max(a, b)` is at least either argument.
///   `clamp(v, lo, hi)` lies within its bounds, and panics rather than returning outside them.
///   `saturating_sub(a, b)` is at most `a`, and strictly below it when `b` is positive and `a`
///   is too, because the result is `a - b` when that does not underflow and zero when it would.
/// What a callee outside the standard library is proved to return, computed from its own body.
///
/// The library summaries below are a finite lookup table: four names, four theorems. A callee
/// the author did not anticipate has no entry, and the inliner has already declined it at this
/// point in the pipeline, so the body holds an opaque `Call` and nothing relates the result to
/// anything. The only route left is to analyse the callee and intersect, over every path that
/// can return, the relations it establishes between its result and its parameters.
///
/// Depth is capped and self-calls are refused. A callee asking for its own optimized MIR would
/// re-enter the query that is currently producing it.
fn callee_summary<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    func: &Operand<'tcx>,
    seed: &[Fact],
    depth: u32,
) -> Vec<(usize, bool)> {
    if depth >= 2 {
        return Vec::new();
    }
    let Some(constant) = func.constant() else { return Vec::new() };
    let ty::FnDef(callee, _) = *constant.const_.ty().kind() else { return Vec::new() };
    let here = body.source.def_id();
    if callee == here || !tcx.is_mir_available(callee) {
        return Vec::new();
    }
    // Asking for a callee's optimized MIR re-enters the query currently producing this body
    // whenever that callee can reach back here, and a self-call is only the simplest case of
    // it: the cycle that first broke this was mutual recursion two crates down. The inliner
    // faces the identical hazard and settles it with this call-graph query, which refuses
    // constructors and may bail on a deep graph. A callee in another crate is already
    // optimized, so it cannot close a cycle through the body being compiled now.
    if let Some(callee_local) = callee.as_local() {
        let Some(root) = here.as_local() else { return Vec::new() };
        if tcx.is_constructor(here) {
            return Vec::new();
        }
        let Some(cyclic) = tcx.mir_callgraph_cyclic(root) else { return Vec::new() };
        if cyclic.contains(&callee_local) {
            return Vec::new();
        }
    }
    let callee_body = tcx.optimized_mir(callee);
    if callee_body.arg_count == 0 {
        return Vec::new();
    }
    let live = reachable(callee_body);
    let entry = solve_seeded(tcx, callee_body, &live, seed, depth + 1);

    let result = Ref::Local(RETURN_PLACE);
    let mut agreed: Option<Vec<(usize, bool)>> = None;
    for (bb, data) in callee_body.basic_blocks.iter_enumerated() {
        if !live[bb] || !matches!(data.terminator().kind, TerminatorKind::Return) {
            continue;
        }
        let Some(mut facts) = entry[bb].clone() else { continue };
        if contradictory(&facts) {
            continue;
        }
        walk(data, data.statements.len(), &mut facts);
        close(&mut facts);
        if contradictory(&facts) {
            continue;
        }
        let mut here: Vec<(usize, bool)> = Vec::new();
        for index in 1..=callee_body.arg_count {
            let param = Ref::Local(Local::from_usize(index));
            for strict in [true, false] {
                if facts.contains(&(result, param, strict)) {
                    here.push((index, strict));
                }
            }
        }
        agreed = Some(match agreed {
            None => here,
            Some(prior) => prior.into_iter().filter(|fact| here.contains(fact)).collect(),
        });
    }
    agreed.unwrap_or_default()
}

fn call_facts<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    data: &BasicBlockData<'tcx>,
    succ: BasicBlock,
    holding: &[Fact],
    depth: u32,
) -> Vec<Fact> {
    let Some(terminator) = &data.terminator else { return Vec::new() };
    let TerminatorKind::Call { func, args, destination, target, .. } = &terminator.kind else {
        return Vec::new();
    };
    // Only the returning edge carries the result; the unwind edge never assigns it.
    if *target != Some(succ) || !destination.projection.is_empty() {
        return Vec::new();
    }
    let Some((krate, item)) = callee_name(tcx, func) else { return Vec::new() };
    let outside_library = krate != "core" && krate != "std";
    let dest = Ref::Local(destination.local);
    let side = |index: usize| -> Option<Ref> { operand_side(&args.get(index)?.node) };

    if outside_library {
        // Carry whatever is known about each actual argument onto the matching formal, so the
        // callee is analysed under the caller's preconditions rather than in isolation.
        //
        // Both sides have to be resolved through the block's copies first. An argument reaches
        // a call through a temporary, so the operand here is that temporary while everything
        // the caller proved is recorded against the original local. Comparing the two as
        // written never matches, and the callee is then analysed with no preconditions at all.
        let alias = walk(data, data.statements.len(), &mut Vec::new());
        let mut seed: Vec<Fact> = Vec::new();
        for index in 0..args.len() {
            let Some(actual) = side(index).map(|arg| root_ref(&alias, arg)) else { continue };
            let param = Ref::Local(Local::from_usize(index + 1));
            for &(low, high, strict) in holding {
                if root_ref(&alias, high) == actual && matches!(low, Ref::Const(_)) {
                    seed.push((low, param, strict));
                }
            }
        }
        return callee_summary(tcx, body, func, &seed, depth)
            .into_iter()
            .filter_map(|(index, strict)| {
                side(index - 1).map(|arg| (dest, root_ref(&alias, arg), strict))
            })
            .collect();
    }

    if item == "min" {
        return [side(0), side(1)]
            .into_iter()
            .flatten()
            .map(|argument| (dest, argument, false))
            .collect();
    }
    if item == "max" {
        let mut out: Vec<Fact> = [side(0), side(1)]
            .into_iter()
            .flatten()
            .map(|argument| (argument, dest, false))
            .collect();
        // The lower bound above is only half of what `max` tells us. It also sits at or below
        // anything both arguments sit at or below, and an argument counts as a bound on itself.
        // That reflexive case is the useful one: `max(j, len)` under a guard proving `j < len`
        // is exactly `len`, so the result can be carried into later arithmetic on `len`, which a
        // lower bound alone never permits. A composed bound is strict only when both halves are,
        // since one argument reaching the bound is enough to put the maximum there too.
        if let (Some(first), Some(second)) = (side(0), side(1)) {
            let upper = |of: Ref| -> Vec<(Ref, bool)> {
                let mut bounds: Vec<(Ref, bool)> = holding
                    .iter()
                    .filter(|&&(low, _, _)| low == of)
                    .map(|&(_, high, strict)| (high, strict))
                    .collect();
                bounds.push((of, false));
                bounds
            };
            for (bound, first_strict) in upper(first) {
                for (other, second_strict) in upper(second) {
                    if bound == other && bound != dest {
                        out.push((dest, bound, first_strict && second_strict));
                    }
                }
            }
        }
        return out;
    }
    if item == "clamp" {
        let mut out = Vec::new();
        if let Some(low) = side(1) {
            out.push((low, dest, false));
        }
        if let Some(high) = side(2) {
            out.push((dest, high, false));
        }
        return out;
    }
    if item == "saturating_sub" {
        let Some(from) = side(0) else { return Vec::new() };
        let mut out = vec![(dest, from, false)];
        // The strict form needs `from` to be positive, and that is a precondition to discharge
        // rather than a postcondition to assert: `saturating_sub(0, 3)` is zero, so claiming
        // the result is strictly below its input would be false exactly when the input is zero,
        // and a false relation here deletes a check that can fail.
        let positive = lower_bound(holding, from).is_some_and(|least| least >= 1);
        if positive && matches!(side(1), Some(Ref::Const(amount)) if amount > 0) {
            out.push((dest, from, true));
        }
        return out;
    }
    Vec::new()
}
