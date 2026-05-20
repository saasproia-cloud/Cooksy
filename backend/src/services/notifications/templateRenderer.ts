import type { NotificationTemplate } from "./types.js";

/**
 * Substitute `{variable}` placeholders in template copy. Tolerant by
 * design — missing variables are flagged so the dispatcher can decide
 * to skip + fall back to a simpler template instead of shipping a
 * literal `{recipe_title}` to the user.
 *
 * Whitespace inside braces is OK (`{ recipe_title }` works). Unknown
 * placeholders in the copy that aren't declared in template.variables
 * are left as-is — they'll surface in the rendered output and be
 * caught by smoke tests.
 */

const PLACEHOLDER_RE = /\{\s*([a-z0-9_]+)\s*\}/gi;

export interface RenderResult {
  title: string;
  body: string;
  missingVariables: string[];
}

export function renderTemplate(
  template: NotificationTemplate,
  variables: Record<string, string | number> = {}
): RenderResult {
  const missing: Set<string> = new Set();

  const substitute = (input: string): string =>
    input.replace(PLACEHOLDER_RE, (_, name: string) => {
      const lookup = variables[name];
      if (lookup === undefined || lookup === null || lookup === "") {
        missing.add(name);
        return `{${name}}`;
      }
      return String(lookup);
    });

  return {
    title: substitute(template.title_fr),
    body: substitute(template.body_fr),
    missingVariables: Array.from(missing)
  };
}

/**
 * The deep_link column may itself contain a placeholder (e.g.
 * `cooksy://recipe/{recipe_id}`). Same substitution rules.
 */
export function renderDeepLink(
  deepLink: string | null,
  variables: Record<string, string | number> = {}
): string | null {
  if (!deepLink) {
    return null;
  }
  const missing: Set<string> = new Set();
  const rendered = deepLink.replace(PLACEHOLDER_RE, (_, name: string) => {
    const lookup = variables[name];
    if (lookup === undefined || lookup === null || lookup === "") {
      missing.add(name);
      return `{${name}}`;
    }
    return String(lookup);
  });
  // If the deep link still has unresolved placeholders, drop it — better
  // to land on Home than to crash the URL parser.
  if (missing.size > 0) {
    return null;
  }
  return rendered;
}
