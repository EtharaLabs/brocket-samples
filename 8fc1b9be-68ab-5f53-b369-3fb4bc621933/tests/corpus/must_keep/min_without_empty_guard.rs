// MUST KEEP. The same shape as the removable min case with the emptiness guard deleted.
// With len 0, `len - 1` wraps to usize::MAX under -O, min(i, MAX) is i, and s[i] panics.
// Punishes applying a min summary without discharging the subtraction's no-wrap precondition.
pub fn f(s: &[u32], i: usize) -> u32 {
    let j = i.min(s.len() - 1);
    s[j]
}
