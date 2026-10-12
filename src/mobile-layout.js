// One responsive breakpoint shared by JS navigation and mobile landscape CSS.
// Phone landscape can have a CSS viewport wider than 820px.
export const MOBILE_NAV_QUERY = '(max-width:820px), (hover:none) and (pointer:coarse) and (max-height:700px)';
export const usesMobileNavigation = (match=matchMedia) => match(MOBILE_NAV_QUERY).matches;
