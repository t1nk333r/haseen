//! Go's `sort.Slice` (pdqsort, `sort/zsortfunc.go`), ported because it is
//! not stable and the generator depends on where it leaves equal elements:
//! median cut splits a bucket at the middle of its pixels sorted by one OKLab
//! axis, and two pixels equal on that axis but not on the others land on
//! either side according to the algorithm. Rust's sorts would put them
//! elsewhere and change the palette.

/// Sorts `v` with `less`, moving elements exactly as Go's `sort.Slice` does.
pub fn sort_slice<T>(v: &mut [T], less: impl Fn(&T, &T) -> bool) {
    let n = v.len();
    let limit = usize::BITS - n.leading_zeros();
    let mut d = Data { v, less: &less };
    pdqsort(&mut d, 0, n, limit as usize);
}

struct Data<'a, T, F: Fn(&T, &T) -> bool> {
    v: &'a mut [T],
    less: &'a F,
}

impl<T, F: Fn(&T, &T) -> bool> Data<'_, T, F> {
    fn less(&self, i: usize, j: usize) -> bool {
        (self.less)(&self.v[i], &self.v[j])
    }
    fn swap(&mut self, i: usize, j: usize) {
        self.v.swap(i, j);
    }
}

#[derive(PartialEq)]
enum Hint {
    Unknown,
    Increasing,
    Decreasing,
}

fn insertion_sort<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, a: usize, b: usize) {
    for i in a + 1..b {
        let mut j = i;
        while j > a && d.less(j, j - 1) {
            d.swap(j, j - 1);
            j -= 1;
        }
    }
}

fn sift_down<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, lo: usize, hi: usize, first: usize) {
    let mut root = lo;
    loop {
        let mut child = 2 * root + 1;
        if child >= hi {
            break;
        }
        if child + 1 < hi && d.less(first + child, first + child + 1) {
            child += 1;
        }
        if !d.less(first + root, first + child) {
            return;
        }
        d.swap(first + root, first + child);
        root = child;
    }
}

fn heap_sort<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, a: usize, b: usize) {
    let first = a;
    let hi = b - a;
    // Only reached with more than 12 elements, so hi - 1 is not negative.
    for i in (0..=(hi - 1) / 2).rev() {
        sift_down(d, i, hi, first);
    }
    for i in (0..hi).rev() {
        d.swap(first, first + i);
        sift_down(d, 0, i, first);
    }
}

fn pdqsort<T, F: Fn(&T, &T) -> bool>(
    d: &mut Data<T, F>,
    mut a: usize,
    mut b: usize,
    mut limit: usize,
) {
    const MAX_INSERTION: usize = 12;
    let mut was_balanced = true;
    let mut was_partitioned = true;
    loop {
        let length = b - a;
        if length <= MAX_INSERTION {
            insertion_sort(d, a, b);
            return;
        }
        if limit == 0 {
            heap_sort(d, a, b);
            return;
        }
        if !was_balanced {
            break_patterns(d, a, b);
            limit -= 1;
        }
        let (mut pivot, mut hint) = choose_pivot(d, a, b);
        if hint == Hint::Decreasing {
            reverse_range(d, a, b);
            pivot = (b - 1) - (pivot - a);
            hint = Hint::Increasing;
        }
        if was_balanced
            && was_partitioned
            && hint == Hint::Increasing
            && partial_insertion_sort(d, a, b)
        {
            return;
        }
        if a > 0 && !d.less(a - 1, pivot) {
            a = partition_equal(d, a, b, pivot);
            continue;
        }
        let (mid, already) = partition(d, a, b, pivot);
        was_partitioned = already;
        let (left, right) = (mid - a, b - mid);
        let balance_threshold = length / 8;
        if left < right {
            was_balanced = left >= balance_threshold;
            pdqsort(d, a, mid, limit);
            a = mid + 1;
        } else {
            was_balanced = right >= balance_threshold;
            pdqsort(d, mid + 1, b, limit);
            b = mid;
        }
    }
}

// i and j are signed in Go: j can step below a while scanning.
fn partition<T, F: Fn(&T, &T) -> bool>(
    d: &mut Data<T, F>,
    a: usize,
    b: usize,
    pivot: usize,
) -> (usize, bool) {
    d.swap(a, pivot);
    let (mut i, mut j) = (a as isize + 1, b as isize - 1);
    let a_ = a;
    while i <= j && d.less(i as usize, a_) {
        i += 1;
    }
    while i <= j && !d.less(j as usize, a_) {
        j -= 1;
    }
    if i > j {
        d.swap(j as usize, a_);
        return (j as usize, true);
    }
    d.swap(i as usize, j as usize);
    i += 1;
    j -= 1;
    loop {
        while i <= j && d.less(i as usize, a_) {
            i += 1;
        }
        while i <= j && !d.less(j as usize, a_) {
            j -= 1;
        }
        if i > j {
            break;
        }
        d.swap(i as usize, j as usize);
        i += 1;
        j -= 1;
    }
    d.swap(j as usize, a_);
    (j as usize, false)
}

fn partition_equal<T, F: Fn(&T, &T) -> bool>(
    d: &mut Data<T, F>,
    a: usize,
    b: usize,
    pivot: usize,
) -> usize {
    d.swap(a, pivot);
    let (mut i, mut j) = (a as isize + 1, b as isize - 1);
    loop {
        while i <= j && !d.less(a, i as usize) {
            i += 1;
        }
        while i <= j && d.less(a, j as usize) {
            j -= 1;
        }
        if i > j {
            break;
        }
        d.swap(i as usize, j as usize);
        i += 1;
        j -= 1;
    }
    i as usize
}

fn partial_insertion_sort<T, F: Fn(&T, &T) -> bool>(
    d: &mut Data<T, F>,
    a: usize,
    b: usize,
) -> bool {
    const MAX_STEPS: usize = 5;
    const SHORTEST_SHIFTING: usize = 50;
    let mut i = a + 1;
    for _ in 0..MAX_STEPS {
        while i < b && !d.less(i, i - 1) {
            i += 1;
        }
        if i == b {
            return true;
        }
        if b - a < SHORTEST_SHIFTING {
            return false;
        }
        d.swap(i, i - 1);
        if i - a >= 2 {
            let mut j = i - 1;
            while j >= 1 {
                if !d.less(j, j - 1) {
                    break;
                }
                d.swap(j, j - 1);
                j -= 1;
            }
        }
        if b - i >= 2 {
            let mut j = i + 1;
            while j < b {
                if !d.less(j, j - 1) {
                    break;
                }
                d.swap(j, j - 1);
                j += 1;
            }
        }
    }
    false
}

fn break_patterns<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, a: usize, b: usize) {
    let length = b - a;
    if length >= 8 {
        let mut random = length as u64;
        let modulus = 1usize << (usize::BITS - length.leading_zeros());
        let lo = a + (length / 4) * 2 - 1;
        for idx in lo..=a + (length / 4) * 2 + 1 {
            random ^= random << 13;
            random ^= random >> 7;
            random ^= random << 17;
            let mut other = (random as usize) & (modulus - 1);
            if other >= length {
                other -= length;
            }
            d.swap(idx, a + other);
        }
    }
}

fn choose_pivot<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, a: usize, b: usize) -> (usize, Hint) {
    const SHORTEST_NINTHER: usize = 50;
    const MAX_SWAPS: usize = 4 * 3;
    let l = b - a;
    let mut swaps = 0;
    let mut i = a + l / 4;
    let mut j = a + l / 4 * 2;
    let mut k = a + l / 4 * 3;
    if l >= 8 {
        if l >= SHORTEST_NINTHER {
            i = median(d, i - 1, i, i + 1, &mut swaps);
            j = median(d, j - 1, j, j + 1, &mut swaps);
            k = median(d, k - 1, k, k + 1, &mut swaps);
        }
        j = median(d, i, j, k, &mut swaps);
    }
    match swaps {
        0 => (j, Hint::Increasing),
        MAX_SWAPS => (j, Hint::Decreasing),
        _ => (j, Hint::Unknown),
    }
}

fn order2<T, F: Fn(&T, &T) -> bool>(
    d: &Data<T, F>,
    a: usize,
    b: usize,
    swaps: &mut usize,
) -> (usize, usize) {
    if d.less(b, a) {
        *swaps += 1;
        return (b, a);
    }
    (a, b)
}

fn median<T, F: Fn(&T, &T) -> bool>(
    d: &Data<T, F>,
    a: usize,
    b: usize,
    c: usize,
    swaps: &mut usize,
) -> usize {
    let (a, b) = order2(d, a, b, swaps);
    let (b, c) = order2(d, b, c, swaps);
    let _ = c;
    let (_, b) = order2(d, a, b, swaps);
    b
}

fn reverse_range<T, F: Fn(&T, &T) -> bool>(d: &mut Data<T, F>, a: usize, b: usize) {
    let (mut i, mut j) = (a, b - 1);
    while i < j {
        d.swap(i, j);
        i += 1;
        j -= 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts() {
        let mut v: Vec<u32> = (0..1000).map(|i| (i * 7919 + 13) % 1009).collect();
        sort_slice(&mut v, |a, b| a < b);
        assert!(v.windows(2).all(|w| w[0] <= w[1]));
        let mut v: Vec<u32> = (0..300).rev().collect();
        sort_slice(&mut v, |a, b| a < b);
        assert!(v.windows(2).all(|w| w[0] <= w[1]));
    }

    // Where Go 1.27's sort.Slice leaves equal keys: the tags of
    // (key, tag) pairs sorted by key alone, printed by Go for the same input.
    #[test]
    fn equal_keys_land_where_go_puts_them() {
        let mut v: Vec<(u32, u32)> = (0..64).map(|i| ((i * 37 % 64) / 8, i)).collect();
        sort_slice(&mut v, |a, b| a.0 < b.0);
        let tags: Vec<u32> = v.iter().map(|p| p.1).collect();
        assert_eq!(tags, GO_TAGS);
    }

    const GO_TAGS: [u32; 64] = [
        52, 33, 14, 45, 0, 59, 26, 7, 28, 9, 54, 21, 40, 35, 2, 47, 16, 4, 30, 61, 49, 11, 42, 23,
        44, 25, 6, 37, 56, 51, 18, 63, 32, 58, 13, 1, 46, 27, 20, 39, 3, 41, 22, 8, 60, 53, 15, 34,
        10, 43, 29, 17, 48, 62, 36, 55, 12, 57, 24, 5, 38, 31, 19, 50,
    ];

    #[test]
    fn a_longer_run_with_many_ties_is_gos() {
        let mut w: Vec<(u32, u32)> = (0..700u32)
            .map(|i| ((i * 7919 + 13) % 1009 % 11, i))
            .collect();
        sort_slice(&mut w, |a, b| a.0 < b.0);
        let mut s: u64 = 0;
        for (i, x) in w.iter().enumerate() {
            s = s
                .wrapping_mul(31)
                .wrapping_add(x.1 as u64)
                .wrapping_add(i as u64);
        }
        assert_eq!(s, 13367475065794000138);
    }
}
