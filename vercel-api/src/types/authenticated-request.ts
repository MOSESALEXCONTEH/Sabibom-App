export type AuthenticatedIdentity = {
  uid: string;
  email?: string;
};

export type BusinessPermission =
  | "use_sabi"
  | "read_business_data"
  | "edit_business_profile"
  | "upload_business_logo";

export type BusinessMembership = {
  role: string;
  isOwner: boolean;
};
