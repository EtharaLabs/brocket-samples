// The bound was read before the container shrank, so the check can fail.
pub fn f(v: &mut Vec<u32>) -> u32 {
    let mut t = 0;
    for i in 0..v.len() {
        v.pop();
        t += v[i];
    }
    t
}
