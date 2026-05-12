---
name: react-container-pattern
description: "Code review skill that enforces the Container/Presentational component separation pattern — containers handle state and logic, presentational components only render UI via props."
when_to_use: "TRIGGER when: reviewing .tsx files that define React components. SKIP when: file is not a React component file."
user-invocable: false
paths:
  - "**/*.tsx"
---

# React Container Pattern

## Rules

### Rule 1: Separate container logic from presentational rendering

React components must follow the Container/Presentational pattern. Container components handle state management, data fetching, and business logic, then pass data and callbacks as props to presentational components. Presentational components must only render UI based on their props — they must not contain hooks like `useState`, `useEffect`, or data-fetching logic.

**Severity:** Critical

**Applies to:** All `.tsx` files

**Example violation:**
```tsx
// UserProfile.tsx — mixes logic and presentation
export const UserProfile = () => {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    fetchUser().then(setUser);
  }, []);

  return (
    <div className="profile">
      <h1>{user?.name}</h1>
      <p>{user?.email}</p>
    </div>
  );
};
```

**Example fix:**
```tsx
// UserProfileContainer.tsx — handles logic
export const UserProfileContainer = () => {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    fetchUser().then(setUser);
  }, []);

  return <UserProfile user={user} />;
};
```

```tsx
// UserProfile.tsx — presentational only
interface UserProfileProps {
  user: User | null;
}

export const UserProfile = ({ user }: UserProfileProps): JSX.Element => (
  <div className="profile">
    <h1>{user?.name}</h1>
    <p>{user?.email}</p>
  </div>
);
```
