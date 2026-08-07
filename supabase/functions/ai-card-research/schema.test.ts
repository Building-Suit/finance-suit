import { assert, assertEquals } from "jsr:@std/assert@1";
import { providerResultSchema, toGeminiSchema } from "./schema.ts";

Deno.test("providerResultSchema is strict OpenAI-dialect JSON Schema", () => {
  assertEquals(providerResultSchema.additionalProperties, false);
  assert(providerResultSchema.required.includes("productMatch"));
});

Deno.test("toGeminiSchema converts nullable type arrays to nullable:true", () => {
  const converted = toGeminiSchema({ type: ["string", "null"] });
  assertEquals(converted.type, "string");
  assertEquals(converted.nullable, true);
});

Deno.test("toGeminiSchema strips additionalProperties recursively", () => {
  const converted = toGeminiSchema(providerResultSchema);
  assertEquals(converted.additionalProperties, undefined);
  const fields = converted.properties.fields;
  assertEquals(fields.additionalProperties, undefined);
  assertEquals(fields.properties.defaultDueDay.additionalProperties, undefined);
});

Deno.test("toGeminiSchema preserves non-nullable primitive types unchanged", () => {
  const converted = toGeminiSchema({ type: "string", enum: ["a", "b"] });
  assertEquals(converted.type, "string");
  assertEquals(converted.nullable, undefined);
  assertEquals(converted.enum, ["a", "b"]);
});
