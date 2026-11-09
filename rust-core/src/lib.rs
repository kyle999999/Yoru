//! Pure Rust domain logic. Apple Calendar supplies local civil-day ordinals,
//! so DST/timezone conversion stays identical to the native app.
use std::collections::BTreeSet;

pub fn streak(days: &[i64], today: i64) -> [i64; 4] {
    let days: BTreeSet<i64> = days.iter().copied().filter(|d| *d <= today).collect();
    let active = days.contains(&today);
    let mut cursor = if active {
        today
    } else {
        today.saturating_sub(1)
    };
    let mut current = 0;
    while days.contains(&cursor) {
        current += 1;
        match cursor.checked_sub(1) {
            Some(previous) => cursor = previous,
            None => break,
        }
    }
    let (mut longest, mut run, mut previous) = (0, 0, None);
    for &day in &days {
        run = if previous.and_then(|p: i64| p.checked_add(1)) == Some(day) {
            run + 1
        } else {
            1
        };
        longest = longest.max(run);
        previous = Some(day);
    }
    [current, longest, days.len() as i64, i64::from(active)]
}

/// Inputs and output are borrowed only for the duration of this call.
/// # Safety
/// Non-null `days` must reference `len` initialized i64 values; `out` must
/// reference four writable i64 values. No Rust-owned memory crosses the ABI.
#[no_mangle]
pub unsafe extern "C" fn yoru_rust_streak(
    days: *const i64,
    len: usize,
    today: i64,
    out: *mut i64,
) -> i32 {
    if out.is_null() || (len != 0 && days.is_null()) || len > isize::MAX as usize / 8 {
        return 0;
    }
    let input = if len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(days, len) }
    };
    let result = streak(input, today);
    unsafe { std::ptr::copy_nonoverlapping(result.as_ptr(), out, 4) };
    1
}

#[no_mangle]
pub extern "C" fn yoru_rust_progress(watched: i64, delta: i64, total: i64, has_total: i32) -> i64 {
    let next = watched.saturating_add(delta).max(0);
    if has_total != 0 {
        total.min(next)
    } else {
        next
    }
}

// Ordered error codes retain existing native validation messages.
#[no_mangle]
pub extern "C" fn yoru_rust_validate_journal(
    has_text: i32,
    future: i32,
    rating: i64,
    has_rating: i32,
    episode: i64,
    has_episode: i32,
    total: i64,
    has_total: i32,
) -> i32 {
    if has_text == 0 {
        return 1;
    }
    if future != 0 {
        return 2;
    }
    if has_rating != 0 && !(1..=10).contains(&rating) {
        return 3;
    }
    if has_episode != 0 && (episode < 1 || (has_total != 0 && episode > total)) {
        return 4;
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dedup_future_and_gap() {
        assert_eq!(streak(&[1, 1, 2, 3, 6, 7], 6), [1, 3, 4, 1]);
    }
    #[test]
    fn yesterday_grace() {
        assert_eq!(streak(&[8, 9], 10), [2, 2, 2, 0]);
    }
    #[test]
    fn empty_and_stale() {
        assert_eq!(streak(&[], 10), [0, 0, 0, 0]);
        assert_eq!(streak(&[1], 10), [0, 1, 1, 0]);
    }
    #[test]
    fn progress_limits() {
        assert_eq!(yoru_rust_progress(11, 5, 12, 1), 12);
        assert_eq!(yoru_rust_progress(0, -1, 0, 0), 0);
        assert_eq!(yoru_rust_progress(12, 1, 0, 0), 13);
    }
    #[test]
    fn journal_errors() {
        assert_eq!(yoru_rust_validate_journal(0, 1, 11, 1, 0, 1, 12, 1), 1);
        assert_eq!(yoru_rust_validate_journal(1, 1, 11, 1, 0, 1, 12, 1), 2);
        assert_eq!(yoru_rust_validate_journal(1, 0, 11, 1, 0, 1, 12, 1), 3);
        assert_eq!(yoru_rust_validate_journal(1, 0, 10, 1, 13, 1, 12, 1), 4);
        assert_eq!(yoru_rust_validate_journal(1, 0, 10, 1, 13, 1, 0, 0), 0);
    }
    #[test]
    fn ffi_null_and_empty() {
        unsafe {
            let mut out = [-1; 4];
            assert_eq!(
                yoru_rust_streak(std::ptr::null(), 0, 10, out.as_mut_ptr()),
                1
            );
            assert_eq!(out, [0, 0, 0, 0]);
            assert_eq!(
                yoru_rust_streak(std::ptr::null(), 1, 10, out.as_mut_ptr()),
                0
            );
        }
    }
}
