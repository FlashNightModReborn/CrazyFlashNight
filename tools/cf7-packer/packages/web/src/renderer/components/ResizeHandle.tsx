export default function ResizeHandle({
  orientation,
  title,
  isActive,
  onStartResize
}: {
  orientation: "horizontal" | "vertical";
  title: string;
  isActive?: boolean;
  onStartResize: (clientX: number, clientY: number) => void;
}) {
  return (
    <div
      className={`resize-handle resize-handle-${orientation} ${isActive ? "resize-handle-active" : ""}`}
      title={title}
      onMouseDown={(event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        onStartResize(event.clientX, event.clientY);
      }}
    >
      <span className="resize-handle-grip" />
    </div>
  );
}
