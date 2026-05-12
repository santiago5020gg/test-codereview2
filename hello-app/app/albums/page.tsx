interface Album {
  id: number;
  userId: number;
  title: string;
}

interface AlbumListProps {
  albums: Album[];
}

function AlbumList({ albums }: AlbumListProps): React.ReactElement {
  return (
    <main style={{ maxWidth: "800px", margin: "0 auto", padding: "2rem" }}>
      <h1>Albums</h1>
      <ul style={{ listStyle: "none", padding: 0 }}>
        {albums.map((album) => (
          <li
            key={album.id}
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
                width: "1.75rem",
                height: "1.75rem",
                borderRadius: "4px",
                backgroundColor: "#6366f1",
                color: "#fff",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: "0.75rem",
                flexShrink: 0,
              }}
            >
              {album.id}
            </span>
            <span>{album.title}</span>
          </li>
        ))}
      </ul>
    </main>
  );
}

export default async function AlbumsPage(): Promise<React.ReactElement> {
  const response = await fetch("https://jsonplaceholder.typicode.com/albums");
  const albums: Album[] = await response.json();

  return <AlbumList albums={albums} />;
}
