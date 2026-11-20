pub fn f(s: &[u32], i: usize, j: usize, k: usize) -> u32 {
    let n = s.len();
    if i < n && j < n && k < n { return s[i.max(j).max(k)]; }
    0
}
