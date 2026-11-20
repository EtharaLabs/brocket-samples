#[inline(never)]
fn cap(x: usize, n: usize) -> usize { if n == 0 { 0 } else if x < n { x } else { n - 1 } }
pub fn f(s: &[u32], x: usize) -> u32 { if s.is_empty() { return 0; } s[cap(x, s.len())] }
