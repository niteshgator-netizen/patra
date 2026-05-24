const DEFAULT_TITLE = 'Patra';

export const updateTabTitle = unreadCount => {
  const count = Number(unreadCount) || 0;
  document.title = count > 0 ? `(${count}) ${DEFAULT_TITLE}` : DEFAULT_TITLE;
};

export const getTotalUnreadCount = conversations =>
  (conversations || []).reduce(
    (sum, chat) => sum + (chat.status === 'open' ? chat.unread_count || 0 : 0),
    0
  );
