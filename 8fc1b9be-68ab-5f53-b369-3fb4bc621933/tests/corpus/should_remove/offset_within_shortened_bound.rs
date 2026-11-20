pub fn f(s: &[u32]) -> u32 {
    let mut t = 0;
    if s.len() >= 2 {
        for i in 0..s.len() - 1 {
            t += s[i + 1];
        }
    }
    t
}
