pub fn f(s: &[u32], i: usize, j: usize) -> u32 {
    let n = s.len();
    if i < n { return s[i.max(j)] }
    0
}
