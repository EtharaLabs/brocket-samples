pub fn f(s: &[u32]) -> u32 {
    let mut t = 0;
    for i in 0..s.len() {
        t += s[i];
    }
    t
}
