#[inline(never)]
fn shrink(mut x: usize, n: usize) -> usize {
    if n == 0 { return 0; }
    while x >= n { x /= 2; }
    x
}
pub fn f(s: &[u32], x: usize) -> u32 { s[shrink(x, s.len())] }
