export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Uploads"


export { Presign } from "../Uploads/Presign"

export * as PresignErrors from "../Uploads/Presign/errors"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { PresignedUpload } from "../Uploads/Types/PresignedUpload/PresignedUpload"

export { FormField } from "../Uploads/Types/FormField/FormField"

