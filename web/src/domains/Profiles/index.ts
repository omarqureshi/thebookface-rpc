export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Profiles"


export { GetProfile } from "../Profiles/GetProfile"


export { UpdateProfile } from "../Profiles/UpdateProfile"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { ProfileModel } from "../Profiles/Types/ProfileModel/ProfileModel"

