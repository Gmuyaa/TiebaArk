

export interface RawSearchPostEntry {

  tid?: string;

  pid?: string;

  title?: string;

  content?: string;

  fname?: string;

  time?: string;
  author?: RawSearchPostAuthor;
}

export interface RawSearchPostAuthor {
  name?: string;
  name_show?: string;
}

export interface RawSearchPostPage {
  current_page?: string;
  total_page?: string;
  has_more?: string;
}

export interface RawSearchPostResponse {
  post_list?: RawSearchPostEntry[];
  page?: RawSearchPostPage;
  error_code?: number;
  error_msg?: string;
}
