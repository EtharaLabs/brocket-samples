// The bound comes from a different slice.
pub fn f(a: &[u32], b: &[u32]) -> u32 {
    let mut t = 0;
    for i in 0..b.len() {
        t += a[i];
    }
    t
}
