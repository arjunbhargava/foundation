import { expect, test } from "vitest";
import { estimateVariance } from "./variance.ts";

// Four values that share an offset of 1e9. Their deviations from their mean,
// 1e9 + 10, are -6, -3, 3, and 6, so their sample variance is exactly
// (36 + 9 + 9 + 36) / 3 = 30.
const OFFSET_VALUES = [4, 7, 13, 16].map((deviation) => 1e9 + deviation);
const EXACT_VARIANCE = 30;

// Chan, Golub, and LeVeque (1983, Table 1) bound the relative rounding error
// of Welford's method by about n·κ·ε, where ε = 2⁻⁵³ and the condition number
// κ = √(1 + n·mean² / Σ(x − mean)²) is 2.1e8 for these values: 9.4e-8. This
// tolerance, 1e-6 relative, is about 10 times that. The textbook one-pass
// formula, bounded by n·κ²·ε ≈ 20, returns -170.67 here, and dividing by n
// rather than n − 1 returns 22.5.
const VARIANCE_TOLERANCE = 3e-5;

test("estimateVariance keeps its precision when the values share a large offset", () => {
	const variance = estimateVariance(OFFSET_VALUES);
	expect(
		Math.abs(variance - EXACT_VARIANCE),
		`estimateVariance returned ${variance}`,
	).toBeLessThanOrEqual(VARIANCE_TOLERANCE);
});

test("estimateVariance accepts exactly 2 values", () => {
	// Deviations from the mean, 2, are -1 and 1: (1 + 1) / (2 - 1) = 2.
	expect(estimateVariance([1, 3])).toBe(2);
});

test.each([
	{ values: [], count: 0 },
	{ values: [5], count: 1 },
])(
	"estimateVariance rejects $count values with a RangeError that states the count",
	({ values, count }) => {
		expect(() => estimateVariance(values)).toThrow(RangeError);
		expect(() => estimateVariance(values)).toThrow(
			`estimateVariance needs at least 2 values, got ${count}`,
		);
	},
);
