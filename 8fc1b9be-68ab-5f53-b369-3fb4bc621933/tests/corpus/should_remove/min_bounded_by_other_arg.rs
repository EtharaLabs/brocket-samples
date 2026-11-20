// Isolates the min summary: no subtraction anywhere. k <= j and j < len gives k < len.
pub fn f(s: &[u32], i: usize, j: usize) -> u32 {
    let k = i.min(j);
    if j < s.len() { s[k] } else { 0 }
}
