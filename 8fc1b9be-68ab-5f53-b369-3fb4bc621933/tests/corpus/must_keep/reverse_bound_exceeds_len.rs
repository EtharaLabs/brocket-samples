// n is unrelated to the slice length.
pub fn f(s: &[u32], n: usize) -> u32 {
    let mut t = 0;
    for i in (0..n).rev() {
        t += s[i];
    }
    t
}
