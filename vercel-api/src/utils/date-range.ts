export function periodBounds(period: string): {start: Date; end: Date} {
  const end = new Date();
  const start = new Date(end);
  if (period === "yesterday") {
    start.setDate(start.getDate() - 1);
    start.setHours(0, 0, 0, 0);
    end.setHours(0, 0, 0, 0);
  } else if (period === "week") {
    const day = start.getDay();
    const diff = day === 0 ? 6 : day - 1;
    start.setDate(start.getDate() - diff);
    start.setHours(0, 0, 0, 0);
  } else if (period === "month") {
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
  } else if (period === "all") {
    start.setFullYear(start.getFullYear() - 10);
    start.setHours(0, 0, 0, 0);
  } else {
    start.setHours(0, 0, 0, 0);
  }
  return {start, end};
}

export function periodLabel(period: string): string {
  switch (period) {
    case "yesterday":
      return "Yesterday";
    case "week":
      return "This week";
    case "month":
      return "This month";
    case "all":
      return "All time";
    default:
      return "Today";
  }
}
