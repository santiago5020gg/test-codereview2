# Naming Conventions

## Rules

### Rule 1: No single-letter variables

Variables must have descriptive names. Single-letter variable names (except `i`, `j`, `k` in loops, or `e` in catch blocks) are not allowed.

**Severity:** Recommended

**Applies to:** All code files

**Example violation:**
```typescript
const x = getUser();
const d = new Date();
```

**Example fix:**
```typescript
const user = getUser();
const currentDate = new Date();
```

### Rule 2: Boolean variables must use is/has/should/can prefix

Boolean variables and function return values should use a prefix that indicates they are boolean.

**Severity:** Recommended

**Applies to:** `.ts`, `.tsx`, `.js`, `.jsx`

**Example violation:**
```typescript
const loading = true;
const admin = user.role === 'admin';
```

**Example fix:**
```typescript
const isLoading = true;
const isAdmin = user.role === 'admin';
```
