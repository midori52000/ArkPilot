import { InstalledSkill, SkillsRegistryJson, SkillEntryJson } from './SkillTypes';
import {
  getSkillsRegistry, saveSkillsRegistry, computeDirHash
} from '../backend/CodexNative';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';

interface BundledSkillDef {
  id: string;
  directory: string;
  skillMd: string;
}

const SKILL_BRAINSTORMING = `---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design and get user approval.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Checklist

1. **Explore project context** - check files, docs, recent commits
2. **Ask clarifying questions** - one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** - with trade-offs and your recommendation
4. **Present design** - in sections scaled to their complexity, get user approval after each section
5. **Write design doc** - save to docs and commit

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, get approval before moving on
`;

const SKILL_FIND_SKILLS = `---
name: find-skills
description: Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities.
---

# Find Skills

This skill helps you discover and install skills from the open agent skills ecosystem.

## When to Use This Skill

Use this skill when the user:

- Asks "how do I do X" where X might be a common task with an existing skill
- Says "find a skill for X" or "is there a skill for X"
- Asks "can you do X" where X is a specialized capability
- Expresses interest in extending agent capabilities
- Wants to search for tools, templates, or workflows

## How to Help Users Find Skills

### Step 1: Understand What They Need

When a user asks for help with something, identify:

1. The domain (e.g., React, testing, design, deployment)
2. The specific task (e.g., writing tests, creating animations, reviewing PRs)
3. Whether this is a common enough task that a skill likely exists

### Step 2: Search for Skills

Search the skills.sh directory for relevant skills matching the user's need.

### Step 3: Verify Quality Before Recommending

**Do not recommend a skill based solely on search results.** Always verify:

1. **Install count** - Prefer skills with 1K+ installs
2. **Source reputation** - Official sources are more trustworthy than unknown authors

### Step 4: Present Options to the User

When you find relevant skills, present them with:

1. The skill name and what it does
2. The install count and source
3. A link to learn more

## Common Skill Categories

| Category        | Example Queries                          |
| --------------- | ---------------------------------------- |
| Web Development | react, nextjs, typescript, css, tailwind |
| Testing         | testing, jest, playwright, e2e           |
| DevOps          | deploy, docker, kubernetes, ci-cd        |
| Documentation   | docs, readme, changelog, api-docs        |
| Code Quality    | review, lint, refactor, best-practices   |
| Design          | ui, ux, design-system, accessibility     |

## When No Skills Are Found

If no relevant skills exist, acknowledge that no existing skill was found and offer to help with the task directly.
`;

const SKILL_FRONTEND_DESIGN = `---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications. Generates creative, polished code and UI design that avoids generic AI aesthetics.
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:

- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision.

## Frontend Aesthetics Guidelines

Focus on:

- **Typography**: Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial and Inter.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid palettes.
- **Motion**: Use animations for effects and micro-interactions. Focus on high-impact moments.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow.
- **Backgrounds & Visual Details**: Create atmosphere and depth. Add contextual effects and textures.

NEVER use generic AI-generated aesthetics like overused font families, cliched color schemes, predictable layouts, or cookie-cutter design.

Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code. Minimalist designs need restraint and precision.
`;

const BUNDLED_DEFS: BundledSkillDef[] = [
  {
    id: 'bundled:brainstorming',
    directory: 'brainstorming',
    skillMd: SKILL_BRAINSTORMING
  },
  {
    id: 'bundled:find-skills',
    directory: 'find-skills',
    skillMd: SKILL_FIND_SKILLS
  },
  {
    id: 'bundled:frontend-design',
    directory: 'frontend-design',
    skillMd: SKILL_FRONTEND_DESIGN
  }
];

/**
 * 首次启动时安装预设 Skill
 * 如果 registry 中已存在同名 skill 则跳过
 *
 * @param codexHome - 应用 codex-home 目录路径
 */
export function installBundledSkills(codexHome: string): void {
  const ssotDir = `${codexHome}/skills`;

  // 迁移：旧 SSOT 路径 `{codexHome}/../.agents/skills` → 新路径 `{codexHome}/skills`
  const oldSsotDir = `${codexHome}/../.agents/skills`;
  try {
    const oldEntries = fileIo.listFileSync(oldSsotDir) as string[];
    for (const entry of oldEntries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const oldPath = `${oldSsotDir}/${entry}`;
      const newPath = `${ssotDir}/${entry}`;
      try {
        const stat = fileIo.statSync(oldPath);
        if (stat.isDirectory()) {
          try {
            fileIo.statSync(newPath);
            // 新路径已存在，跳过
          } catch (_) {
            // 新路径不存在，移动
            try {
              fileIo.mkdirSync(ssotDir, true);
            } catch (_) { /* 目录已存在 */ }
            fileIo.renameSync(oldPath, newPath);
          }
        }
      } catch (_) { /* skip */ }
    }
  } catch (_) {
    // 旧目录不存在，无需迁移
  }

  // 读取现有 registry
  let existing: InstalledSkill[] = [];
  try {
    const json = getSkillsRegistry(codexHome);
    const parsed: SkillsRegistryJson = JSON.parse(json) as SkillsRegistryJson;
    const entries: SkillEntryJson[] = parsed.skills ?? [];
    existing = entries.map((e: SkillEntryJson) => InstalledSkill.fromJSON(e));
  } catch (_) {
    // registry 不存在或为空，继续安装
  }

  const now = Date.now();
  const newSkills: InstalledSkill[] = [];

  for (const def of BUNDLED_DEFS) {
    // 跳过已存在的
    const alreadyInstalled = existing.some((s: InstalledSkill) => s.directory === def.directory);
    if (alreadyInstalled) {
      continue;
    }

    // 写入 SSOT 目录
    const destDir = `${ssotDir}/${def.directory}`;
    try {
      fileIo.mkdirSync(destDir, true);
    } catch (_) {
      // 目录已存在
    }
    const skillMdPath = `${destDir}/SKILL.md`;
    const file = fileIo.openSync(skillMdPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    const encoder = new util.TextEncoder();
    const encoded = encoder.encodeInto(def.skillMd);
    fileIo.writeSync(file.fd, encoded.buffer);
    fileIo.closeSync(file);

    // 计算哈希
    const contentHash = computeDirHash(destDir);

    // 解析 name / description
    let name = def.directory;
    let description = '';
    const parts = def.skillMd.split('---');
    if (parts.length >= 3) {
      const frontMatter = parts[1].trim();
      const lines = frontMatter.split('\n');
      for (const line of lines) {
        const colonIdx = line.indexOf(':');
        if (colonIdx === -1) {
          continue;
        }
        const key = line.substring(0, colonIdx).trim();
        const value = line.substring(colonIdx + 1).trim().replace(/^['"]|['"]$/g, '');
        if (key === 'name') {
          name = value;
        }
        if (key === 'description') {
          description = value;
        }
      }
    }

    const entry = new InstalledSkill(
      def.id, name, description, def.directory,
      'local', '', '', '',
      '', true, now, contentHash, 0
    );
    newSkills.push(entry);
  }

  if (newSkills.length === 0) {
    return;
  }

  // 合并写入 registry
  const merged = [...existing, ...newSkills];
  const registry: SkillsRegistryJson = {
    version: 1,
    skills: merged as SkillEntryJson[],
    updatedAt: new Date(now).toISOString()
  };
  saveSkillsRegistry(codexHome, JSON.stringify(registry));
}
