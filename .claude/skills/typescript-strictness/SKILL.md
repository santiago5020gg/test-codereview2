---
name: typescript-strictness
description: "Code review skill that enforces strict TypeScript practices: no `any` type, explicit function return types, and interface/type definitions for all component props."
when_to_use: "TRIGGER when: reviewing .ts or .tsx files. SKIP when: file is not a TypeScript file."
user-invocable: false
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Strictness

## Rules

### Rule 1: No `any` type

Never use the `any` type. Use specific types, generics, or `unknown` when the type is truly uncertain. This preserves type safety and prevents silent runtime errors.

**Severity:** Critical

**Applies to:** All `.ts` and `.tsx` files

**Example violation:**
```typescript
function parseResponse(data: any): any {
  return data.results.map((item: any) => item.name);
}
```

**Example fix:**
```typescript
interface ApiResponse {
  results: Array<{ name: string }>;
}

function parseResponse(data: ApiResponse): string[] {
  return data.results.map((item) => item.name);
}
```

### Rule 2: Explicit function return types

All functions and methods must declare an explicit return type. This prevents accidental return type changes and improves code readability.

**Severity:** Critical

**Applies to:** All `.ts` and `.tsx` files

**Example violation:**
```typescript
function calculateTotal(items: CartItem[]) {
  return items.reduce((sum, item) => sum + item.price, 0);
}
```

**Example fix:**
```typescript
function calculateTotal(items: CartItem[]): number {
  return items.reduce((sum, item) => sum + item.price, 0);
}
```

### Rule 3: Props must use interface or type

All React component props must be defined with an explicit `interface` or `type` alias. Inline object types in parameter signatures are not allowed.

**Severity:** Critical

**Applies to:** All `.tsx` files

**Example violation:**
```tsx
export const Button = ({ label, onClick }: { label: string; onClick: () => void }): JSX.Element => (
  <button onClick={onClick}>{label}</button>
);
```

**Example fix:**
```tsx
interface ButtonProps {
  label: string;
  onClick: () => void;
}

export const Button = ({ label, onClick }: ButtonProps): JSX.Element => (
  <button onClick={onClick}>{label}</button>
);
```
