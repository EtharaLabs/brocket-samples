// G2: `saturating_sub` postcondition, result <= receiver, and never wraps.
pub fn f(s: &[u32]) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let j = s.len().saturating_sub(3);
    s[j]
}
