/**
 * Estimate the variance of a population from a sample of it.
 *
 * Returns the unbiased sample variance: the sum of squared deviations from
 * the sample mean, divided by one less than the number of values. It is
 * computed with Welford's method, whose rounding error grows with the size of
 * the values' mean relative to their spread, not with its square as the
 * textbook formula's `(Σx² − (Σx)²/n) / (n − 1)` does. Values that share a
 * large offset, such as timestamps, therefore keep their precision.
 *
 * Takes O(n) time and O(1) memory, and iterates `values` once.
 *
 * @param values - The sample, in any order; at least 2 values. Any iterable
 *   works, including a generator. A NaN or infinite value makes the result
 *   NaN.
 * @returns The sample variance, in the square of the values' unit; ≥ 0.
 * @throws `RangeError` if `values` yields fewer than 2 values.
 *
 * @example
 * ```ts
 * estimateVariance([1e9 + 4, 1e9 + 7, 1e9 + 13, 1e9 + 16]); // 30
 * ```
 */
export function estimateVariance(values: Iterable<number>): number {
	let count = 0;
	let mean = 0;
	let sumOfSquaredDeviations = 0;
	for (const value of values) {
		count += 1;
		const deviationFromPreviousMean = value - mean;
		mean += deviationFromPreviousMean / count;
		sumOfSquaredDeviations += deviationFromPreviousMean * (value - mean);
	}

	if (count < 2) {
		throw new RangeError(
			`estimateVariance needs at least 2 values, got ${count}`,
		);
	}
	return sumOfSquaredDeviations / count;
}
