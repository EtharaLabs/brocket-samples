#[inline(never)]
fn last(n: usize) -> usize { if n == 0 { 0 } else { n - 1 } }
pub fn f(s: &[u32]) -> u32 { s[last(s.len())] }
