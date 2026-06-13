/**
 * AMF0 type markers (Action Message Format 0).
 *
 * Reference: Adobe AMF0 spec. Only the markers that occur in Flash
 * SharedObject (.sol) bodies written by the AVM1/AS2 runtime are fully
 * supported here. MOVIECLIP / RECORDSET / AVMPLUS are recognized but rejected
 * (they never appear in CF7 AS2 saves).
 */
export const AMF0 = {
  NUMBER: 0x00,
  BOOLEAN: 0x01,
  STRING: 0x02,
  OBJECT: 0x03,
  MOVIECLIP: 0x04,
  NULL: 0x05,
  UNDEFINED: 0x06,
  REFERENCE: 0x07,
  ECMA_ARRAY: 0x08,
  OBJECT_END: 0x09,
  STRICT_ARRAY: 0x0a,
  DATE: 0x0b,
  LONG_STRING: 0x0c,
  UNSUPPORTED: 0x0d,
  RECORDSET: 0x0e,
  XML_DOCUMENT: 0x0f,
  TYPED_OBJECT: 0x10,
  AVMPLUS: 0x11,
} as const;

/** SharedObject envelope constants. */
export const SOL = {
  /** First two bytes of every .sol file. */
  SIGNATURE: 0x00bf,
  /** ASCII "TCSO" magic that follows the 4-byte length field. */
  MAGIC: 'TCSO',
  /** The fixed 6 bytes between TCSO and the SharedObject name (0x000400000000). */
  HEADER_PAD: Uint8Array.from([0x00, 0x04, 0x00, 0x00, 0x00, 0x00]),
} as const;
