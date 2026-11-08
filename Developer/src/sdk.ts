import { validateManifest } from './validation.ts';
import type { WebManifest } from './web-types.ts';
export type * from './web-types.ts';
export { validateManifest, validateEvent } from './validation.ts';
export { safeTarget, launchURL } from './targets.ts';
/** Validates metadata. Does not build, transform, render or host an interface. */
export function defineWebApp(manifest:WebManifest):WebManifest { return validateManifest(manifest); }
