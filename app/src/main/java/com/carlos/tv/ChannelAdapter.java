package com.carlos.tv;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ChannelHolder> {

    public interface Listener {
        void onChannelSelected(Channel channel);

        void onFavoriteChanged(Channel channel);
    }

    private final List<Channel> items = new ArrayList<>();
    private final LayoutInflater inflater;
    private final Listener listener;
    private final LogoLoader logoLoader = new LogoLoader();
    private final int favoriteColor;
    private final int normalColor;

    public ChannelAdapter(Context context, Listener listener) {
        this.inflater = LayoutInflater.from(context);
        this.listener = listener;
        this.favoriteColor = context.getColor(R.color.carlos_lime);
        this.normalColor = context.getColor(R.color.carlos_text_secondary);
    }

    public void submit(List<Channel> channels) {
        items.clear();
        items.addAll(channels);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public ChannelHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        return new ChannelHolder(inflater.inflate(R.layout.item_channel, parent, false));
    }

    @Override
    public void onBindViewHolder(@NonNull ChannelHolder holder, int position) {
        Channel channel = items.get(position);
        holder.name.setText(channel.getName());
        holder.metadata.setText(channel.getMetadata());

        String initial = channel.getName().isEmpty()
                ? "TV"
                : channel.getName().substring(0, 1).toUpperCase(Locale.getDefault());
        logoLoader.load(channel.getLogoUrl(), holder.logo, holder.initial, initial);

        holder.favorite.setText(channel.isFavorite() ? "★" : "☆");
        holder.favorite.setTextColor(channel.isFavorite() ? favoriteColor : normalColor);
        holder.favorite.setContentDescription(
                holder.itemView.getContext().getString(R.string.favorite_description));

        holder.favorite.setOnClickListener(view -> {
            int adapterPosition = holder.getBindingAdapterPosition();
            if (adapterPosition == RecyclerView.NO_POSITION) {
                return;
            }
            channel.setFavorite(!channel.isFavorite());
            notifyItemChanged(adapterPosition);
            listener.onFavoriteChanged(channel);
        });
        holder.itemView.setOnClickListener(view -> listener.onChannelSelected(channel));
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    public void release() {
        logoLoader.shutdown();
    }

    static final class ChannelHolder extends RecyclerView.ViewHolder {
        private final ImageView logo;
        private final TextView initial;
        private final TextView name;
        private final TextView metadata;
        private final TextView favorite;

        private ChannelHolder(@NonNull View itemView) {
            super(itemView);
            logo = itemView.findViewById(R.id.channel_logo);
            initial = itemView.findViewById(R.id.channel_initial);
            name = itemView.findViewById(R.id.channel_name);
            metadata = itemView.findViewById(R.id.channel_metadata);
            favorite = itemView.findViewById(R.id.channel_favorite);
        }
    }
}
