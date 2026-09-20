import { handleRequest } from "./handler.ts";

Deno.serve((request) => handleRequest(request));
