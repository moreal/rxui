function decodeError(message) {
  return {
    ok: false,
    error: { code: "LRX-PORT-302", message: `issue response decode failed: ${message}` },
  };
}

const NUMBER_PREFIX = "\u0000leanrx-json-number:";
const MAX_SAFE_ID = 9007199254740991n;

function preserveNumberLexemes(body) {
  let output = "";
  let index = 0;
  while (index < body.length) {
    if (body[index] === '"') {
      const start = index++;
      let escaped = false;
      while (index < body.length) {
        const character = body[index++];
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === '"') break;
      }
      output += body.slice(start, index);
      continue;
    }
    const number = body.slice(index).match(
      /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/,
    );
    if (number) {
      output += JSON.stringify(`${NUMBER_PREFIX}${number[0]}`);
      index += number[0].length;
    } else {
      output += body[index++];
    }
  }
  return output;
}

function exactNaturalId(value) {
  if (typeof value !== "string" || !value.startsWith(NUMBER_PREFIX)) return null;
  const token = value.slice(NUMBER_PREFIX.length);
  const parts = token.match(
    /^(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/,
  );
  if (!parts) return null;
  const fraction = parts[3] ?? "";
  const exponent = BigInt(parts[4] ?? "0");
  const scale = exponent - BigInt(fraction.length);
  if (scale < 0n) return null;
  const coefficient = BigInt(`${parts[2]}${fraction}`);
  if (parts[1] === "-" && coefficient !== 0n) return null;
  if (coefficient === 0n) return 0;
  const digits = coefficient.toString().length;
  if (BigInt(digits) + scale > 16n) return null;
  const result = coefficient * (10n ** scale);
  return result <= MAX_SAFE_ID ? Number(result) : null;
}

export function decodeIssueResponse(response) {
  if (response.status !== 200) {
    return {
      ok: false,
      error: {
        code: "LRX-PORT-303",
        message: `issue request returned HTTP ${String(response.status)}`,
      },
    };
  }
  let value;
  let lexicalValue;
  try {
    value = JSON.parse(response.body);
    lexicalValue = JSON.parse(preserveNumberLexemes(response.body));
  } catch (error) {
    return decodeError(error instanceof Error ? error.message : String(error));
  }
  if (!value || typeof value !== "object" || !Array.isArray(value.issues) ||
      typeof value.hasMore !== "boolean") {
    return decodeError("object with issues array and hasMore boolean expected");
  }
  const issues = [];
  const ids = new Set();
  for (let index = 0; index < value.issues.length; index += 1) {
    const issue = value.issues[index];
    const lexicalIssue = lexicalValue?.issues?.[index];
    const exactId = exactNaturalId(lexicalIssue?.id);
    if (!issue || typeof issue !== "object" || exactId === null || issue.id !== exactId ||
        typeof issue.title !== "string") {
      return decodeError("issue id must be a natural number and title must be a string");
    }
    if (ids.has(exactId)) {
      return {
        ok: false,
        error: { code: "LRX-PORT-304", message: "issue response contains duplicate IDs" },
      };
    }
    ids.add(exactId);
    issues.push([exactId, issue.title]);
  }
  return { ok: true, value: [issues, value.hasMore] };
}
