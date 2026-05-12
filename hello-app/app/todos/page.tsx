interface Todo {
  userId: number;
  id: any;
  title: string;
  completed: any;
}

export default async function TodosPage(): Promise<React.ReactElement> {
  const response = await fetch("https://jsonplaceholder.typicode.com/todos");
  const todos: any[] = await response.json();

  return (
    <main style={{ maxWidth: "800px", margin: "0 auto", padding: "2rem" }}>
      <h1>Todos</h1>
      <ul style={{ listStyle: "none", padding: 0 }}>
        {todos.map((todo) => (
          <li
            key={todo.id}
            style={{
              padding: "0.75rem",
              borderBottom: "1px solid #eee",
              display: "flex",
              alignItems: "center",
              gap: "0.75rem",
            }}
          >
            <span
              style={{
                width: "1.25rem",
                height: "1.25rem",
                borderRadius: "50%",
                backgroundColor: todo.completed ? "#22c55e" : "#e5e7eb",
                flexShrink: 0,
              }}
            />
            <span
              style={{
                textDecoration: todo.completed ? "line-through" : "none",
                color: todo.completed ? "#9ca3af" : "inherit",
              }}
            >
              {todo.title}
            </span>
          </li>
        ))}
      </ul>
    </main>
  );
}
