interface Props {
  orientation: "horizontal" | "vertical";
  title: string;
  isActive?: boolean;
  onStartResize: (clientX: number, clientY: number) => void;
}

/** A thin draggable splitter. Identical interaction model to cf7-packer. */
export default function ResizeHandle({ orientation, title, isActive, onStartResize }: Props) {
  return (
    <div
      className={`resize-handle resize-handle-${orientation} ${isActive ? "resize-handle-active" : ""}`}
      title={title}
      role="separator"
      aria-orientation={orientation === "vertical" ? "vertical" : "horizontal"}
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
