pub fn f(s: &[u32]) -> u32 {
    let mut t = 0;
    for i in 0..s.len() {
        for j in 0..=i {
            t += s[j];
        }
    }
    t
}
