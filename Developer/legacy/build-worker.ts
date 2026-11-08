import { pathToFileURL } from 'node:url';
import { validate } from './validation.ts';
try {process.send?.({ok:true,configuration:validate((await import(pathToFileURL(process.argv[2]).href)).default)});}
catch {process.send?.({ok:false});}
process.disconnect?.();
