// G2: provable only from the postcondition of an opaque callee.
// `Ord::min` is not inlined at this pipeline position, so the index arrives as the return of
// a call. Single-body dataflow sees nothing relating it to the length.
pub fn f(s: &[u32], i: usize) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let j = i.min(s.len() - 1);
    s[j]
}
