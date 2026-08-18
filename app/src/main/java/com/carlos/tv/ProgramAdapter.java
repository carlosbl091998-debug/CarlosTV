package com.carlos.tv;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;

public final class ProgramAdapter extends RecyclerView.Adapter<ProgramAdapter.Holder> {
    public interface Listener { void onProgramSelected(XuperProgram program); }

    private final List<XuperProgram> items = new ArrayList<>();
    private final Listener listener;
    private final LogoLoader loader = new LogoLoader();

    public ProgramAdapter(Listener listener) { this.listener = listener; }

    public void submit(List<XuperProgram> programs) {
        items.clear();
        if (programs != null) items.addAll(programs);
        notifyDataSetChanged();
    }

    @NonNull @Override
    public Holder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        return new Holder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_program, parent, false));
    }

    @Override public void onBindViewHolder(@NonNull Holder h, int position) {
        XuperProgram p = items.get(position);
        h.title.setText(p.getName());
        String meta = p.getCategory();
        if (!p.getCountry().isEmpty()) meta += " · " + p.getCountry();
        h.meta.setText(meta);
        String initial = p.getName().isEmpty() ? "C" : p.getName().substring(0,1).toUpperCase();
        loader.load(p.getPosterUrl(), h.poster, h.fallback, initial);
        h.itemView.setOnClickListener(v -> listener.onProgramSelected(p));
    }

    @Override public int getItemCount() { return items.size(); }
    public void release() { loader.shutdown(); }

    static final class Holder extends RecyclerView.ViewHolder {
        final ImageView poster;
        final TextView fallback;
        final TextView title;
        final TextView meta;
        Holder(View v) {
            super(v);
            poster = v.findViewById(R.id.program_poster);
            fallback = v.findViewById(R.id.program_fallback);
            title = v.findViewById(R.id.program_title);
            meta = v.findViewById(R.id.program_meta);
        }
    }
}
