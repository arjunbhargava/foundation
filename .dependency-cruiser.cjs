// Module boundaries, which `mise run lint:typescript` checks with depcruise.
// Add a rule to `forbidden` for each one:
// https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md
/** @type {import("dependency-cruiser").IConfiguration} */
module.exports = {
	forbidden: [
		{
			name: "library-code-imports-no-dev-dependency",
			comment:
				"Library code imports a package from devDependencies, such as vitest. A production install (pnpm install --prod) leaves those out, so the import fails there. Move test-only code into a *.test.ts file.",
			severity: "error",
			from: { path: "^packages/[^/]+/src/", pathNot: "\\.test\\.ts$" },
			to: { dependencyTypes: ["npm-dev"] },
		},
	],
	options: {
		// The tools, vitest included, are devDependencies of the root
		// package.json, not of each package's. Without this, dependency-cruiser
		// reads only the package's own, finds them unlisted, and the rule above
		// never matches.
		combinedDependencies: true,
		doNotFollow: { path: "node_modules" },
	},
};
