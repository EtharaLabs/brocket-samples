pub fn f(s: &[u32]) -> u32 {
    let mut t = 0;
    let mut i = 0;
    while i < s.len() {
        t += s[i];
        i += 1;
    }
    t
}
