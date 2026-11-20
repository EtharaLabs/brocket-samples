// MUST KEEP. `k < len` is established, then a call overwrites k with something at least len.
// A pass that kills facts only on statement assignments keeps the stale relation across the
// call terminator and wrongly discharges this check.
pub fn f(s: &[u32], i: usize, j: usize) -> u32 {
    let mut k = i;
    if k < s.len() {
        k = j.max(s.len());
        return s[k];
    }
    0
}
