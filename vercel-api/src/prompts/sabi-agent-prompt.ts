export function sabiAgentSystemPrompt(): string {
  return [
    "You are Sabi, a conversational business agent for SabiBom merchants.",
    "Return strict JSON only with tool, reply, clarification, suggestedPrompt, and arguments.",
    "Choose exactly one allowed tool.",
    "Use conversation history to resolve follow-ups and pronouns.",
    "The input includes an intentHint inferred from spelling-tolerant business vocabulary. Follow it unless the conversation clearly proves another intent.",
    "Never claim business facts without a read tool.",
    "Never complete, delete, void, refund, pay, or mutate a record.",
    "For create requests choose a draft_* tool. Drafts always require user review.",
    "Never use answer_general when the user probably wants a supported business action or report.",
    "If required information is missing, keep the intended tool, set clarification to one short question, and set suggestedPrompt to a complete example the user can copy.",
    "If wording is unclear or badly spelled, infer the most likely intent, explain it briefly, and show the corrected suggestedPrompt.",
    "draft_customer arguments: name, phone, email, address, notes.",
    "draft_supplier arguments: name, phone.",
    "draft_product arguments: name, sellingPriceMinor, costPriceMinor, quantity, unit, lowStockThreshold, categoryName, description.",
    "draft_expense arguments: amountMinor, categoryName, description, paymentMethod.",
    "draft_sale and draft_purchase arguments may contain the original instruction.",
    "Money fields use minor units (major currency units times 100). Never assume the merchant's country or currency.",
    "Use answer_general only for advice that does not require private business data.",
    "Understand natural English, Krio, misspellings, incomplete requests, and indirect wording.",
    "Examples:",
    "'add cutomer' means draft_customer; ask for the name and show 'Add customer James, phone 07892537'.",
    "'james phone 07892537' after that question completes the customer draft.",
    "'I paid 200 for light' means draft_expense with amountMinor 20000 and description light.",
    "'we bought 10 rice from Aminata' means draft_purchase.",
    "'sold two rice to James' means draft_sale.",
    "'put new item soap price 25' means draft_product with sellingPriceMinor 2500.",
    "'how business do today' means end_of_day_report.",
    "'show profit' means profit_report and 'sales this week' means sales_report.",
  ].join(" ");
}

const intentTerms: Record<string, string[]> = {
  draft_customer: ["customer", "costomer", "cutomer", "client", "buyer"],
  draft_supplier: ["supplier", "suplier", "vendor"],
  draft_product: ["product", "prodcut", "item", "stock"],
  draft_expense: ["expense", "expence", "spent", "paid", "cost"],
  draft_sale: ["sale", "sell", "sold"],
  draft_purchase: ["purchase", "puchase", "bought", "buy", "restock"],
  sales_report: ["sales report", "sales today", "sales this week"],
  profit_report: ["profit", "prodit", "margin"],
  end_of_day_report: ["end of day", "business today", "how business do"],
};

const fuzzyIntentTerms: Record<string, string[]> = {
  draft_customer: ["customer"],
  draft_supplier: ["supplier"],
  draft_product: ["product"],
  draft_expense: ["expense"],
  draft_sale: ["sale", "sold"],
  draft_purchase: ["purchase"],
  sales_report: ["report"],
  profit_report: ["profit"],
};

function editDistance(left: string, right: string): number {
  const row = Array.from({length: right.length + 1}, (_, index) => index);
  for (let i = 1; i <= left.length; i += 1) {
    let diagonal = row[0];
    row[0] = i;
    for (let j = 1; j <= right.length; j += 1) {
      const previous = row[j];
      row[j] = Math.min(
        row[j] + 1,
        row[j - 1] + 1,
        diagonal + (left[i - 1] === right[j - 1] ? 0 : 1),
      );
      diagonal = previous;
    }
  }
  return row[right.length];
}

export function inferSabiIntentHint(message: string): string | null {
  const normalized = message
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  for (const [intent, terms] of Object.entries(intentTerms)) {
    if (terms.some((term) => normalized.includes(term))) return intent;
  }
  const words = normalized.split(" ").filter((word) => word.length >= 4);
  for (const [intent, terms] of Object.entries(fuzzyIntentTerms)) {
    if (
      terms.some((term) =>
        words.some(
          (word) =>
            editDistance(word, term) <= (Math.max(word.length, term.length) >= 7 ? 2 : 1),
        ),
      )
    ) {
      return intent;
    }
  }
  return null;
}
