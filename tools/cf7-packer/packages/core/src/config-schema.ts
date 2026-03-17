import { z } from "zod";

const layerRuleSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  source: z.string().min(1),
  include: z.array(z.string()).default([]),
  exclude: z.array(z.string()).default([])
});

const packConfigSchema = z.object({
  version: z.number().int().positive(),
  meta: z.object({
    name: z.string().min(1),
    description: z.string().optional()
  }),
  source: z.object({
    mode: z.enum(["worktree", "git-tag"]),
    tag: z.string().nullable().optional().default(null),
    repoRoot: z.string().min(1)
  }),
  output: z.object({
    dir: z.string().min(1),
    clean: z.boolean().default(true),
    minify: z.object({
      enabled: z.boolean().default(false),
      extensions: z.array(z.string()).default([".json", ".xml"])
    }).optional()
  }),
  layers: z.array(layerRuleSchema).min(1),
  globalExclude: z.array(z.string()).default([])
});

export { packConfigSchema, layerRuleSchema };
export type PackConfigRaw = z.input<typeof packConfigSchema>;
