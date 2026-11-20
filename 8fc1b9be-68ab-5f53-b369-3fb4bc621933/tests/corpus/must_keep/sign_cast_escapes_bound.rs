// The guard bounds i, but the round trip through a signed narrow type can produce a
// huge index: i = 200 with len = 300 passes the guard, yet 200 as i8 is -56 and
// -56 as usize is near usize::MAX. The check must stay.
pub fn f(s: &[u32], i: usize) -> u32 {
    if i < s.len() {
        let j = (i as i8) as usize;
        return s[j];
    }
    0
}
