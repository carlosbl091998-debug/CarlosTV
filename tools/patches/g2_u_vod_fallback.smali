.class public final Lm6/g2$u;
.super Lkotlin/jvm/internal/l;
.source "SourceFile"

# interfaces
.implements Lea/l;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lm6/g2;->y0(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;ZZZLjava/lang/String;[IZ)V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x19
    name = null
.end annotation

.field public final synthetic e:Lkotlin/jvm/internal/w;
.field public final synthetic f:Lkotlin/jvm/internal/w;
.field public final synthetic g:Lkotlin/jvm/internal/u;
.field public final synthetic h:Lm6/g2;

.method public constructor <init>(Lkotlin/jvm/internal/w;Lkotlin/jvm/internal/w;Lkotlin/jvm/internal/u;Lm6/g2;)V
    .locals 0
    iput-object p1, p0, Lm6/g2$u;->e:Lkotlin/jvm/internal/w;
    iput-object p2, p0, Lm6/g2$u;->f:Lkotlin/jvm/internal/w;
    iput-object p3, p0, Lm6/g2$u;->g:Lkotlin/jvm/internal/u;
    iput-object p4, p0, Lm6/g2$u;->h:Lm6/g2;
    const/4 p1, 0x1
    invoke-direct {p0, p1}, Lkotlin/jvm/internal/l;-><init>(I)V
    return-void
.end method

.method public final a(Lmobile/com/requestframe/utils/response/StartPlayVODResult;)Ljava/util/HashMap;
    .locals 6
    const-string/jumbo v0, "it"
    invoke-static {p1, v0}, Lkotlin/jvm/internal/k;->g(Ljava/lang/Object;Ljava/lang/String;)V
    iget-object v0, p0, Lm6/g2$u;->e:Lkotlin/jvm/internal/w;
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/StartPlayVODResult;->getData()Lmobile/com/requestframe/utils/response/StartPlayVODData;
    move-result-object v1
    invoke-static {v1}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-virtual {v1}, Lmobile/com/requestframe/utils/response/StartPlayVODData;->getEpisodeList()Ljava/util/List;
    move-result-object v1
    invoke-static {v1}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    const/4 v2, 0x0
    invoke-interface {v1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
    move-result-object v1
    check-cast v1, Lmobile/com/requestframe/utils/response/EpisodeList;
    invoke-virtual {v1}, Lmobile/com/requestframe/utils/response/EpisodeList;->getSubtitleList()Ljava/util/List;
    move-result-object v1
    iput-object v1, v0, Lkotlin/jvm/internal/w;->a:Ljava/lang/Object;
    new-instance v0, Ljava/util/HashMap;
    invoke-direct {v0}, Ljava/util/HashMap;-><init>()V
    new-instance v1, Ljava/util/HashMap;
    invoke-direct {v1}, Ljava/util/HashMap;-><init>()V
    iget-object v3, p0, Lm6/g2$u;->f:Lkotlin/jvm/internal/w;
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/StartPlayVODResult;->getData()Lmobile/com/requestframe/utils/response/StartPlayVODData;
    move-result-object v4
    invoke-static {v4}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-virtual {v4}, Lmobile/com/requestframe/utils/response/StartPlayVODData;->getEpisodeList()Ljava/util/List;
    move-result-object v4
    invoke-static {v4}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-interface {v4, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
    move-result-object v4
    check-cast v4, Lmobile/com/requestframe/utils/response/EpisodeList;
    invoke-virtual {v4}, Lmobile/com/requestframe/utils/response/EpisodeList;->getProgramContentId()Ljava/lang/String;
    move-result-object v4
    if-nez v4, :cond_0
    const-string/jumbo v4, ""
    :cond_0
    iput-object v4, v3, Lkotlin/jvm/internal/w;->a:Ljava/lang/Object;
    iget-object v3, p0, Lm6/g2$u;->g:Lkotlin/jvm/internal/u;
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/StartPlayVODResult;->getData()Lmobile/com/requestframe/utils/response/StartPlayVODData;
    move-result-object v4
    invoke-static {v4}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-virtual {v4}, Lmobile/com/requestframe/utils/response/StartPlayVODData;->getEpisodeList()Ljava/util/List;
    move-result-object v4
    invoke-static {v4}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-interface {v4, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
    move-result-object v4
    check-cast v4, Lmobile/com/requestframe/utils/response/EpisodeList;
    invoke-virtual {v4}, Lmobile/com/requestframe/utils/response/EpisodeList;->getEpisodeNumber()Ljava/lang/Integer;
    move-result-object v4
    if-eqz v4, :cond_1
    invoke-virtual {v4}, Ljava/lang/Integer;->intValue()I
    move-result v4
    goto :goto_0
    :cond_1
    const/4 v4, -0x1
    :goto_0
    iput v4, v3, Lkotlin/jvm/internal/u;->a:I
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/StartPlayVODResult;->getData()Lmobile/com/requestframe/utils/response/StartPlayVODData;
    move-result-object p1
    invoke-static {p1}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/StartPlayVODData;->getEpisodeList()Ljava/util/List;
    move-result-object p1
    invoke-static {p1}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-interface {p1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
    move-result-object p1
    check-cast p1, Lmobile/com/requestframe/utils/response/EpisodeList;
    invoke-virtual {p1}, Lmobile/com/requestframe/utils/response/EpisodeList;->getTotalMovieList()Ljava/util/List;
    move-result-object p1
    invoke-static {p1}, Lkotlin/jvm/internal/k;->d(Ljava/lang/Object;)V
    invoke-interface {p1}, Ljava/lang/Iterable;->iterator()Ljava/util/Iterator;
    move-result-object p1
    :cond_2
    :goto_1
    invoke-interface {p1}, Ljava/util/Iterator;->hasNext()Z
    move-result v2
    if-eqz v2, :cond_8
    invoke-interface {p1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
    move-result-object v2
    check-cast v2, Lmobile/com/requestframe/utils/response/TotalMovieList;
    invoke-virtual {v2}, Lmobile/com/requestframe/utils/response/TotalMovieList;->getQuality()Ljava/lang/String;
    move-result-object v3
    invoke-interface {v1, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    invoke-virtual {v2}, Lmobile/com/requestframe/utils/response/TotalMovieList;->getMovieList()Ljava/util/List;
    move-result-object v3
    invoke-static {v3}, Lcom/mobile/brasiltv/utils/d0;->I(Ljava/util/Collection;)Z
    move-result v3
    if-eqz v3, :cond_2
    # STATIC_VOD_FALLBACK
    const-string/jumbo v3, "480p"
    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    const-string/jumbo v3, "720p"
    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    const-string/jumbo v3, "1080p"
    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
    goto :goto_1
    :cond_8
    iget-object p1, p0, Lm6/g2$u;->h:Lm6/g2;
    invoke-static {p1, v1}, Lm6/g2;->K(Lm6/g2;Ljava/util/HashMap;)V
    iget-object p1, p0, Lm6/g2$u;->h:Lm6/g2;
    invoke-static {p1, v1}, Lm6/g2;->I(Lm6/g2;Ljava/util/HashMap;)V
    return-object v0
.end method

.method public bridge synthetic invoke(Ljava/lang/Object;)Ljava/lang/Object;
    .locals 0
    check-cast p1, Lmobile/com/requestframe/utils/response/StartPlayVODResult;
    invoke-virtual {p0, p1}, Lm6/g2$u;->a(Lmobile/com/requestframe/utils/response/StartPlayVODResult;)Ljava/util/HashMap;
    move-result-object p1
    return-object p1
.end method
