const canvas = document.querySelector("#hero-canvas");
const ctx = canvas.getContext("2d");

const glyphs = ["┌", "─", "┐", "│", "█", "░", "╳", "●", "◇", "◆", "╭", "╯"];
const colors = ["#c7ff45", "#3bd6cc", "#ff7248", "#f2b84b", "#f1ecd9"];

let cells = [];
let width = 0;
let height = 0;
let dpr = 1;
let pointerX = 0.7;
let pointerY = 0.35;

function resize() {
  const rect = canvas.getBoundingClientRect();
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  width = Math.max(1, Math.floor(rect.width));
  height = Math.max(1, Math.floor(rect.height));
  canvas.width = Math.floor(width * dpr);
  canvas.height = Math.floor(height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  buildCells();
}

function buildCells() {
  const step = width < 700 ? 34 : 42;
  const cols = Math.ceil(width / step) + 2;
  const rows = Math.ceil(height / step) + 2;

  cells = Array.from({ length: cols * rows }, (_, index) => {
    const x = (index % cols) * step;
    const y = Math.floor(index / cols) * step;
    return {
      x,
      y,
      step,
      glyph: glyphs[(index * 7 + rows) % glyphs.length],
      color: colors[(index * 5 + cols) % colors.length],
      phase: (index % 17) / 17,
      alpha: 0.1 + ((index * 13) % 20) / 100
    };
  });
}

function draw(time) {
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#10110d";
  ctx.fillRect(0, 0, width, height);
  ctx.font = "700 18px 'Azeret Mono', monospace";
  ctx.textBaseline = "middle";

  const t = time / 1000;
  const driftX = (pointerX - 0.5) * 18;
  const driftY = (pointerY - 0.5) * 18;

  for (const cell of cells) {
    const pulse = 0.5 + Math.sin(t * 1.4 + cell.phase * 8) * 0.5;
    const alpha = cell.alpha + pulse * 0.12;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = cell.color;
    ctx.fillText(cell.glyph, cell.x + driftX * cell.phase, cell.y + driftY * cell.phase);
  }

  ctx.globalAlpha = 0.16;
  ctx.strokeStyle = "#f1ecd9";
  ctx.lineWidth = 1;

  for (let y = 0; y < height; y += 48) {
    ctx.beginPath();
    ctx.moveTo(0, y + 0.5);
    ctx.lineTo(width, y + 0.5);
    ctx.stroke();
  }

  for (let x = 0; x < width; x += 48) {
    ctx.beginPath();
    ctx.moveTo(x + 0.5, 0);
    ctx.lineTo(x + 0.5, height);
    ctx.stroke();
  }

  ctx.globalAlpha = 1;
  requestAnimationFrame(draw);
}

window.addEventListener("resize", resize);
window.addEventListener("pointermove", (event) => {
  pointerX = event.clientX / Math.max(window.innerWidth, 1);
  pointerY = event.clientY / Math.max(window.innerHeight, 1);
});

resize();
requestAnimationFrame(draw);
