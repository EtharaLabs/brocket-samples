#[inline(never)]
fn retreat(n: usize, mut steps: usize) -> usize {
    let mut r = n;
    while r != 0 && steps != 0 { r -= 1; steps -= 1; }
    r
}
pub fn f(s: &[u32], steps: usize) -> u32 {
    if s.is_empty() { return 0; }
    s[retreat(s.len(), steps)]
}
