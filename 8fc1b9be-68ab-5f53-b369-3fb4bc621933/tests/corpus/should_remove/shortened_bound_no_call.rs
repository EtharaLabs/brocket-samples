// Isolates the Sub rule with a strict literal lower bound and no call at all.
pub fn f(s: &[u32], i: usize) -> u32 {
    if s.is_empty() { return 0; }
    let m = s.len() - 1;
    if i < m { s[i] } else { 0 }
}
