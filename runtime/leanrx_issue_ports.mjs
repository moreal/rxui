function decodeError(message) {
  return {
    ok: false,
    error: { code: "LRX-PORT-302", message: `issue response decode failed: ${message}` },
  };
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
  try {
    value = JSON.parse(response.body);
  } catch (error) {
    return decodeError(error instanceof Error ? error.message : String(error));
  }
  if (!value || typeof value !== "object" || !Array.isArray(value.issues) ||
      typeof value.hasMore !== "boolean") {
    return decodeError("object with issues array and hasMore boolean expected");
  }
  const issues = [];
  const ids = new Set();
  for (const issue of value.issues) {
    if (!issue || typeof issue !== "object" || !Number.isSafeInteger(issue.id) ||
        issue.id < 0 || typeof issue.title !== "string") {
      return decodeError("issue id must be a natural number and title must be a string");
    }
    if (ids.has(issue.id)) {
      return {
        ok: false,
        error: { code: "LRX-PORT-304", message: "issue response contains duplicate IDs" },
      };
    }
    ids.add(issue.id);
    issues.push([issue.id, issue.title]);
  }
  return { ok: true, value: [issues, value.hasMore] };
}
