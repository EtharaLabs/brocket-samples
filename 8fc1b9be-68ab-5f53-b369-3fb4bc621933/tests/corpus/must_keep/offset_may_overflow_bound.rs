// i + 1 reaches len on the last iteration.
pub fn f(s: &[u32]) -> u32 {
    let mut t = 0;
    for i in 0..s.len() {
        t += s[i + 1];
    }
    t
}
