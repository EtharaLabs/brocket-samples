pub fn f(a: &[u32], b: &[u32]) -> u32 {
    assert_eq!(a.len(), b.len());
    let mut t = 0;
    for i in 0..a.len() {
        t += a[i] + b[i];
    }
    t
}
