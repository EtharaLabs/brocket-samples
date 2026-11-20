from __future__ import annotations

import itertools
from collections.abc import Iterator

AUTO = ("Send", "Sync")
LEAF = ("u32", "u8", "String", "()")


def _wrap(depth: int, inner: str) -> str:
    for _ in range(depth):
        inner = f"Wrap<{inner}>"
    return inner


def cycle_auto() -> Iterator[tuple[str, str]]:
    for auto, indir, leaf, via_field in itertools.product(AUTO, (1, 2), LEAF, (True, False)):
        chain, prev = [], auto
        for step in range(indir):
            name = f"Indir{step}"
            chain.append(f"trait {name} {{}}\nimpl<T: {prev}> {name} for T {{}}")
            prev = name
        field = "<Foo<T> as Trait>::Assoc" if via_field else "T"
        body = "\n".join(chain)
        yield (
            f"cycle_auto:{auto}:{indir}:{leaf}:{via_field}",
            f"""#![allow(dead_code)]
struct Foo<T>({field});
{body}
trait Trait {{ type Assoc; }}
impl<T: {prev}> Trait for T {{ type Assoc = (); }}
fn is_auto<T: {auto}>() {{}}
pub fn site() {{ is_auto::<Foo<{leaf}>>(); }}
""",
        )


def cycle_proj() -> Iterator[tuple[str, str]]:
    for depth, extra, second in itertools.product((0, 1), (True, False), (True, False)):
        inner = "<T as Foo>::Assoc"
        for _ in range(depth):
            inner = f"<{inner} as Foo>::Assoc"
        bound = "trait Bar {}\nfn needs_bar<S: Bar>() {}" if extra else ""
        other = "trait Other { type A; }\n" if second else ""
        yield (
            f"cycle_proj:{depth}:{extra}:{second}",
            f"""#![allow(dead_code)]
trait Foo {{ type Assoc; }}
{other}{bound}
fn test<T: Foo<Assoc = {inner}>>() {{}}
""",
        )


def cycle_gat() -> Iterator[tuple[str, str]]:
    for has_const, bound_name in itertools.product((True, False), ("Bound", "Sized")):
        member = "const OPS: u32;" if has_const else "fn ops() -> u32;"
        call = "T::Object::OPS" if has_const else "T::Object::ops()"
        extra = "trait Bound {}\n" if bound_name == "Bound" else ""
        yield (
            f"cycle_gat:{has_const}:{bound_name}",
            f"""#![allow(dead_code)]
{extra}trait Alloc {{ {member} }}
trait Driver {{ type Object<Ctx: {bound_name}>: Alloc; }}
fn f<T: Driver>() -> u32 {{ {call} }}
""",
        )


def coherence_hrtb() -> Iterator[tuple[str, str]]:
    for lhs, rhs, outlives in itertools.product(("i32", "u8"), ("u32", "i64"), ("'static", "'a")):
        yield (
            f"coherence_hrtb:{lhs}:{rhs}:{outlives}",
            f"""#![allow(dead_code)]
trait MayRequire {{}}
impl<'a: {outlives}> MayRequire for &'a {lhs} {{}}
impl<'a> MayRequire for &'a {rhs} {{}}
trait Trait {{}}
impl Trait for {lhs} {{}}
impl<T> Trait for T where for<'a> &'a T: MayRequire {{}}
fn is_trait<T: Trait>() {{}}
pub fn site() {{ is_trait::<{lhs}>(); is_trait::<{rhs}>(); }}
""",
        )


def coherence_neg() -> Iterator[tuple[str, str]]:
    for carrier, guard in itertools.product(("Option<T>", "Vec<T>"), ("Clone", "Copy")):
        yield (
            f"coherence_neg:{carrier}:{guard}",
            f"""#![allow(dead_code)]
trait Local {{}}
trait Overlap {{ fn f(); }}
impl<T> Overlap for {carrier} where Self: {guard} {{ fn f() {{}} }}
impl<T> Overlap for {carrier} where Self: Local {{ fn f() {{}} }}
fn test<T>() where {carrier}: {guard} + Local {{
    <{carrier} as Overlap>::f();
}}
""",
        )


def canon_region() -> Iterator[tuple[str, str]]:
    for arity, concrete in itertools.product((2, 3), ("&()", "&u8")):
        params = ", ".join(f"C{i}" for i in range(arity))
        supers = " + ".join(f"B<C{i}>" for i in range(arity))
        args = ", ".join([concrete] * arity)
        yield (
            f"canon_region:{arity}:{concrete}",
            f"""#![allow(dead_code)]
trait B<C> {{}}
impl<C> B<C> for () {{}}
trait D<{params}>: {supers} {{ fn f(&self) {{}} }}
impl<{params}> D<{params}> for () {{}}
pub fn site() {{ (&() as &dyn D<{args}>).f() }}
""",
        )


def canon_paramenv() -> Iterator[tuple[str, str]]:
    for lifetime_bound, gat in itertools.product((True, False), (True, False)):
        assoc = "type Assoc<'a> where Self: 'a;" if gat else "type Assoc;"
        proj = "T::Assoc<'a>" if gat else "T::Assoc"
        eq = "Assoc<'a> = T" if gat else "Assoc = T"
        bound = "Bound<'a>" if lifetime_bound else "Bound"
        decl = "trait Bound<'a> {}" if lifetime_bound else "trait Bound {}"
        call = "impls_bound::<'_, T>()" if lifetime_bound else "impls_bound::<T>()"
        sig = "fn impls_bound<'a, S: Bound<'a>>() {}" if lifetime_bound else "fn impls_bound<S: Bound>() {}"
        yield (
            f"canon_paramenv:{lifetime_bound}:{gat}",
            f"""#![allow(dead_code)]
trait Trait {{ {assoc} }}
{decl}
{sig}
fn foo<'a, T: 'a>()
where
    T: Trait<{eq}> + {bound},
    {proj}: {bound},
{{
    {call};
}}
""",
        )


def opaque_implied() -> Iterator[tuple[str, str]]:
    for carrier, boxed in itertools.product(("Outlives<T>", "(T, Outlives<T>)"), (True, False)):
        head = "Box<dyn core::any::Any>" if boxed else "usize"
        first = "Box::new(x)" if boxed else "0"
        value = "Outlives::<T>(None)" if carrier == "Outlives<T>" else "(x2, Outlives::<T>(None))"
        extra = "" if carrier == "Outlives<T>" else ""
        yield (
            f"opaque_implied:{carrier}:{boxed}",
            f"""#![allow(dead_code)]
struct Outlives<T: 'static>(Option<T>);
fn foo<T: Clone>(x: T) -> ({head}, impl Sized) {{
    let x2 = x.clone();
    let _ = x2;
    ({first}, {value})
}}
{extra}""".replace("x2, Outlives", "x.clone(), Outlives"),
        )


def hrtb_object() -> Iterator[tuple[str, str]]:
    for leaf, supertrait in itertools.product(("u8", "u32"), (True, False)):
        decl = (
            "trait Super<'a> { type A: 'a; }\ntrait Tr<'a>: Super<'a> {}"
            if supertrait
            else "trait Tr<'a> { type A: 'a; }"
        )
        assoc = "Super" if supertrait else "Tr"
        yield (
            f"hrtb_object:{leaf}:{supertrait}",
            f"""#![allow(dead_code)]
{decl}
fn f<X: ?Sized + Tr<'static>>(a: <X as {assoc}<'static>>::A) -> Box<dyn core::any::Any> {{
    Box::new(a)
}}
fn launder<'b>(r: &'b {leaf}) -> &'static {leaf} {{
    *f::<dyn for<'a> Tr<'a, A = &'b {leaf}>>(r).downcast_ref::<&'static {leaf}>().unwrap()
}}
""",
        )


FAMILIES = {
    "cycle_auto": cycle_auto,
    "cycle_proj": cycle_proj,
    "cycle_gat": cycle_gat,
    "coherence_hrtb": coherence_hrtb,
    "coherence_neg": coherence_neg,
    "canon_region": canon_region,
    "canon_paramenv": canon_paramenv,
    "opaque_implied": opaque_implied,
    "hrtb_object": hrtb_object,
}


def programs() -> Iterator[tuple[str, str, str]]:
    for name, family in FAMILIES.items():
        for ident, source in family():
            yield name, ident, source


if __name__ == "__main__":
    import collections

    counts = collections.Counter(name for name, _, _ in programs())
    print(dict(counts), "total", sum(counts.values()))
