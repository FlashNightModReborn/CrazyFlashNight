// The versioned build copies npm three@0.185.1 into ../../vendor. Keeping this
// one typed seam prevents the rest of the presentation layer from depending on
// a browser import map or a legacy global THREE object.
// @ts-expect-error the audited minified ESM intentionally ships without a sibling declaration file
import * as ThreeNamespace from '../../vendor/three.module.min.js';

const THREE: any = ThreeNamespace;
export default THREE;
