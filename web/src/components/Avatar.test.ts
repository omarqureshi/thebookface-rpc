import { describe, expect, it } from "vitest"
import { initialsOf } from "./Avatar"

describe("initialsOf", () => {
  it("uses the first and last name, not the first two", () => {
    // A middle name must not displace the family name.
    expect(initialsOf("Omar Ali Qureshi")).toBe("OQ")
    expect(initialsOf("Ada King Noel Byron Lovelace")).toBe("AL")
  })

  it("keeps a single name to a single letter", () => {
    expect(initialsOf("Omar")).toBe("O")
  })

  it("treats a hyphenated surname as one name", () => {
    // Splitting on the hyphen too would give KM here, and the last name is
    // "Guru-Murthy" rather than "Murthy" — so the split stays whitespace-only.
    expect(initialsOf("Krishnan Guru-Murthy")).toBe("KG")
    expect(initialsOf("Mary-Jane Watson")).toBe("MW")
    expect(initialsOf("Guru-Murthy")).toBe("G")
    expect(initialsOf("Conan O'Brien")).toBe("CO")
  })

  it("handles the ordinary two-part case", () => {
    expect(initialsOf("Ada Lovelace")).toBe("AL")
  })

  it("upcases", () => {
    expect(initialsOf("omar qureshi")).toBe("OQ")
  })

  it("ignores surrounding and repeated whitespace", () => {
    expect(initialsOf("  Omar   Ali   Qureshi  ")).toBe("OQ")
  })

  it("falls back to ? when there is no name", () => {
    // The avatar still renders for a user whose name never arrived.
    expect(initialsOf("")).toBe("?")
    expect(initialsOf("   ")).toBe("?")
    expect(initialsOf(null)).toBe("?")
    expect(initialsOf(undefined)).toBe("?")
  })
})
