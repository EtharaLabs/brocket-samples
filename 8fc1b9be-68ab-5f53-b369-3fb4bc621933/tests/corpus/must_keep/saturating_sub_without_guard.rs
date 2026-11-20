// MUST KEEP. With len 0, saturating_sub(0, 3) is 0 and s[0] panics on an empty slice.
// This is the exact twin of the precondition I nearly asserted instead of discharging.
pub fn f(s: &[u32]) -> u32 {
    let j = s.len().saturating_sub(3);
    s[j]
}
