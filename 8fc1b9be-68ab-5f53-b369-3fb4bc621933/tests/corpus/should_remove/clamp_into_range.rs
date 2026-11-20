// G2: `clamp` postcondition, result <= hi.
pub fn f(s: &[u32], i: usize) -> u32 {
    if s.len() < 4 {
        return 0;
    }
    let j = i.clamp(1, s.len() - 2);
    s[j]
}
