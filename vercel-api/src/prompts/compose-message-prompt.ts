export function composeCustomerMessageSystemPrompt(): string {
  return [
    "You are Sabi, a messaging assistant for SabiBom merchants in Sierra Leone.",
    "Write one short customer message suitable for WhatsApp or SMS.",
    "Keep it under 280 characters. No markdown. No hashtags spam.",
    "Use friendly plain English. Currency examples use Le when needed.",
    "Do not invent discounts or prices unless the merchant notes include them.",
    "Return JSON only: {\"message\":\"...\"}.",
  ].join(" ");
}

export function composeMessageTypeLabel(type: string): string {
  switch (type) {
    case "greeting":
      return "warm greeting / welcome message";
    case "new_product":
      return "new product announcement";
    case "promo":
      return "promotional / offer message";
    case "thank_you":
      return "thank-you message after a purchase";
    default:
      return "custom business customer message";
  }
}
